//! A deterministic-enough, in-process MLS test environment for stateful fuzzing.
//!
//! It builds N real, initialized MLS clients using the same construction the
//! `meet-core` tests use (`MlsClient::new` + a mock SD-CWT issuance), but wired
//! only against the light vendored crates — no `meet-core`, no network, no
//! OpenSSL. One client creates a group; others join via external commit. The
//! harness then routes commit / application messages between members and can
//! drop, replay, reorder, or corrupt them.
//!
//! The MLS API is fully async, so every operation is driven through a
//! single-threaded tokio runtime via `block_on`.
//!
//! NOTE on determinism: key generation uses the system RNG (no injectable seed
//! in the vendored stack), so a crash's *operation sequence* is deterministic
//! but the *crypto material* is not — exact libFuzzer crash reproduction is
//! therefore best-effort. See FUZZING_REPORT.md §"Stateful MLS".
use ed25519_dalek::pkcs8::{DecodePrivateKey, DecodePublicKey};
use ed25519_dalek::{SigningKey, VerifyingKey};
use identity::{Disclosure, Ed25519Issuer, SdCwt};
use meet_identifiers::{Domain, GroupId, Id, LeafIndex};
use mls_rs_codec::{MlsDecode, MlsEncode};
use mls_trait::types::ReceivedMessage;
use mls_trait::{KvExt, MlsClientTrait, MlsGroupEntity, MlsGroupTrait, ProposalArg};
use mls_types::MlsMessage;
use proton_claims::reexports::cose_key_set::CoseKeySet;
use proton_claims::reexports::{Issuer, IssuerParams, SpiceOidcClaims};
use proton_claims::{ClientType, MimiProvider, ProtonMeetClaims, Role};
use proton_meet_mls::kv::MemKv;
use proton_meet_mls::{MlsClient, MlsClientConfig, MlsGroup, MlsGroupConfig};
use std::str::FromStr;

/// Hard-coded mock issuer key (matches the meet-core test helper).
// nosemgrep
const ISSUER_SK_PEM: &str = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";

/// A message in flight between members.
#[derive(Clone)]
pub struct QueuedMsg {
    pub sender: usize,
    pub msg: MlsMessage,
}

/// What a member's decoder produced for a delivered message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecvKind {
    /// Accepted as an application message attributed to leaf `sender`.
    App {
        sender: u32,
        len: usize,
    },
    Commit,
    Proposal,
    Other,
    Err(String),
}

pub struct TestMlsEnv {
    rt: tokio::runtime::Runtime,
    clients: Vec<MlsClient<MemKv>>,
    /// Per-client persistent store handle (the kv groups are serialized into),
    /// used to reload group state from storage.
    store_kv: Vec<MemKv>,
    /// Per-client group handle; `None` until the client has joined / after it leaves.
    groups: Vec<Option<MlsGroup<MemKv>>>,
    /// Per-client leaf index in the group (tracked at join time).
    leaf_of: Vec<Option<LeafIndex>>,
    /// Client indices currently in the group.
    pub active: Vec<usize>,
    /// Messages produced but not yet delivered.
    pub pending: Vec<QueuedMsg>,
    /// Messages already delivered (for replay).
    pub history: Vec<QueuedMsg>,
    /// (freed leaf index, a pre-removal application message from the member who
    /// vacated it). Used by `check_sender_integrity` to detect leaf-reuse
    /// sender aliasing (mls-rs #361).
    tombstones: Vec<(u32, MlsMessage)>,
    /// A member temporarily "offline": commits destined for it are diverted into
    /// `backlog` (in canonical order) instead of delivered, so it can later catch
    /// up. Enables the #352 catch-up scenario (unmerged leaves persist while the
    /// group churns without this member).
    excluded: Option<usize>,
    /// Canonical-order commits withheld from the excluded member.
    backlog: Vec<MlsMessage>,
}

impl TestMlsEnv {
    /// Build `n` initialized clients (no group yet). `n` is clamped to [1, 8].
    pub fn new(n: usize) -> Self {
        let n = n.clamp(1, 8);
        let meeting_id = "fuzz-meeting".to_string();
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");

        let mut clients = Vec::with_capacity(n);
        let mut store_kv = Vec::with_capacity(n);
        for i in 0..n {
            let is_host = i == 0;
            let email = format!("user{i}@proton.me");
            let (client, kv) = rt.block_on(build_client(&email, is_host, &meeting_id));
            clients.push(client);
            store_kv.push(kv);
        }

        let groups = (0..n).map(|_| None).collect();
        let leaf_of = (0..n).map(|_| None).collect();

        Self {
            rt,
            clients,
            store_kv,
            groups,
            leaf_of,
            active: Vec::new(),
            pending: Vec::new(),
            history: Vec::new(),
            tombstones: Vec::new(),
            excluded: None,
            backlog: Vec::new(),
        }
    }

    pub fn num_clients(&self) -> usize {
        self.clients.len()
    }

    fn norm(&self, raw: u8) -> usize {
        (raw as usize) % self.clients.len()
    }

    /// Client 0 creates the group. Idempotent: does nothing if a group exists.
    pub fn create_group(&mut self, host_raw: u8) {
        if !self.active.is_empty() {
            return;
        }
        let host = self.norm(host_raw);
        let rt = &self.rt;
        let group = rt.block_on(async {
            let client = &self.clients[host];
            let user_id = client.user_id().ok()?;
            let unique = format!("fuzzroom_{}", uuid::Uuid::new_v4());
            let group_id = GroupId {
                id: Id::from_str(&unique).ok()?,
                domain: Domain::from_str("meet.proton.me").ok()?,
            };
            let cfg = MlsGroupConfig::default(user_id, true);
            let g = client
                .new_group(&group_id, Disclosure::Full, cfg)
                .await
                .ok()?
                .store()
                .await
                .ok()?;
            Some(g)
        });
        if let Some(g) = group {
            let leaf = self.rt.block_on(async { g.own_leaf_index().ok() });
            self.groups[host] = Some(g);
            self.leaf_of[host] = leaf;
            self.active.push(host);
        }
    }

    /// `joiner` joins via external commit off a fresh group_info from `active[0]`.
    pub fn join(&mut self, joiner_raw: u8) {
        if self.active.is_empty() {
            return;
        }
        let joiner = self.norm(joiner_raw);
        if self.active.contains(&joiner) {
            return;
        }
        let coordinator = self.active[0];

        // 1. Coordinator advances one epoch to mint a fresh group_info + tree.
        let bundle = {
            let g = self.groups[coordinator].as_mut().expect("active group");
            self.rt.block_on(async {
                let (b, _) = g
                    .new_commit([ProposalArg::Update {
                        credential: None,
                        extensions: None,
                        capabilities: None,
                    }])
                    .await
                    .ok()?;
                g.merge_pending_commit().await.ok()?;
                Some(b)
            })
        };
        let Some(bundle) = bundle else { return };
        let (Some(group_info), Some(ratchet_tree)) =
            (bundle.group_info.clone(), bundle.ratchet_tree.clone())
        else {
            return;
        };

        // 2. Other current members process the coordinator's update commit.
        for &m in self.active.clone().iter() {
            if m == coordinator {
                continue;
            }
            self.deliver_to(m, &bundle.commit);
        }

        // 3. Joiner external-joins at that epoch.
        let joined = {
            let client = &self.clients[joiner];
            self.rt.block_on(async {
                let (g, jb) = client
                    .join_group_via_external_commit(
                        group_info,
                        ratchet_tree,
                        Disclosure::Full,
                        vec![],
                    )
                    .await
                    .ok()?;
                let g = g.store().await.ok()?;
                Some((g, jb))
            })
        };
        let Some((jgroup, jbundle)) = joined else {
            return;
        };

        // 4. Deliver the joiner's external commit to all current members.
        for &m in self.active.clone().iter() {
            self.deliver_to(m, &jbundle.commit);
        }

        let leaf = self.rt.block_on(async { jgroup.own_leaf_index().ok() });
        self.groups[joiner] = Some(jgroup);
        self.leaf_of[joiner] = leaf;
        self.active.push(joiner);
    }

    /// `adder` (a current member) adds `addee` (a non-member) via an Add-proposal
    /// commit, then `addee` joins via the welcome. Unlike external-commit `join`,
    /// this leaves `addee`'s leaf **unmerged** at the adder's path ancestors —
    /// the precondition for the mls-rs #352 blank-ancestor parent-hash bug.
    pub fn add_member(&mut self, adder_raw: u8, addee_raw: u8) {
        if self.active.is_empty() {
            return;
        }
        let adder = self.norm(adder_raw);
        if !self.active.contains(&adder) {
            return;
        }
        let addee = self.norm(addee_raw);
        if addee == adder || self.active.contains(&addee) {
            return;
        }

        // addee mints a key package for itself.
        let kp = {
            let client = &self.clients[addee];
            self.rt.block_on(async {
                let (kps, _) = client.new_key_packages(1, Disclosure::Full).await.ok()?;
                kps.into_iter().next()
            })
        };
        let Some(kp) = kp else { return };

        // adder commits the Add (creates an unmerged leaf for addee).
        let bundle = {
            let g = self.groups[adder].as_mut().expect("active group");
            self.rt.block_on(async {
                let (b, _) = g.new_commit([ProposalArg::Add(Box::new(kp))]).await.ok()?;
                g.merge_pending_commit().await.ok()?;
                Some(b)
            })
        };
        let Some(bundle) = bundle else { return };

        // Deliver the add commit to the other current members.
        for &m in self.active.clone().iter() {
            if m == adder {
                continue;
            }
            self.deliver_to(m, &bundle.commit);
        }

        // addee joins via the welcome produced by the add commit.
        let (Some(welcome), Some(tree)) = (bundle.welcome.clone(), bundle.ratchet_tree.clone())
        else {
            return;
        };
        let joined = {
            let client = &self.clients[addee];
            self.rt.block_on(async {
                let (g, _) = client.join_group(welcome, tree).await.ok()?;
                g.store().await.ok()
            })
        };
        let Some(g) = joined else { return };
        let leaf = self.rt.block_on(async { g.own_leaf_index().ok() });
        self.groups[addee] = Some(g);
        self.leaf_of[addee] = leaf;
        self.active.push(addee);
    }

    /// `member` performs a self-update commit; queued for delivery to others.
    pub fn update(&mut self, member_raw: u8) {
        let member = self.norm(member_raw);
        if !self.active.contains(&member) {
            return;
        }
        let bundle = {
            let g = self.groups[member].as_mut().expect("active group");
            self.rt.block_on(async {
                let (b, _) = g
                    .new_commit([ProposalArg::Update {
                        credential: None,
                        extensions: None,
                        capabilities: None,
                    }])
                    .await
                    .ok()?;
                g.merge_pending_commit().await.ok()?;
                Some(b)
            })
        };
        if let Some(b) = bundle {
            self.pending.push(QueuedMsg {
                sender: member,
                msg: b.commit,
            });
        }
    }

    /// Coordinator removes `target` from the group (models remove and leave).
    pub fn remove(&mut self, target_raw: u8) {
        if self.active.len() < 2 {
            return;
        }
        let target = self.norm(target_raw);
        let coordinator = self.active[0];
        // Never remove the coordinator or the temporarily-excluded (catch-up) member.
        if target == coordinator || self.excluded == Some(target) || !self.active.contains(&target)
        {
            return;
        }
        let Some(leaf) = self.leaf_of[target] else {
            return;
        };
        let target_leaf_u32 = *leaf;

        // Capture a pre-removal application message from the member about to be
        // removed, so we can later detect leaf-reuse sender aliasing (#361).
        let ghost = self.encrypt_for(target, b"ghost-from-removed-member");

        let bundle = {
            let g = self.groups[coordinator].as_mut().expect("active group");
            self.rt.block_on(async {
                let (b, _) = g.new_commit([ProposalArg::Remove(leaf)]).await.ok()?;
                g.merge_pending_commit().await.ok()?;
                Some(b)
            })
        };
        let Some(bundle) = bundle else { return };

        // Deliver the remove commit to all members (including the removed one).
        for &m in self.active.clone().iter() {
            if m == coordinator {
                continue;
            }
            self.deliver_to(m, &bundle.commit);
        }
        // Evict the removed member locally.
        self.groups[target] = None;
        self.leaf_of[target] = None;
        self.active.retain(|&m| m != target);

        // Tombstone the freed leaf + the removed member's last message.
        if let Some(m) = ghost {
            self.tombstones.push((target_leaf_u32, m));
        }
    }

    /// Take `member` "offline": subsequent commits destined for it are withheld
    /// into `backlog` (canonical order) rather than delivered. Chosen from the
    /// current members, never the coordinator. Returns the chosen member.
    pub fn set_excluded(&mut self, member_raw: u8) -> Option<usize> {
        if self.active.len() < 2 {
            return None;
        }
        let m = self.norm(member_raw);
        if m == self.active[0] || !self.active.contains(&m) {
            return None;
        }
        self.backlog.clear();
        self.excluded = Some(m);
        Some(m)
    }

    /// Bring the excluded member back online: apply the withheld canonical commit
    /// sequence **in order**. Oracle (targets the mls-rs #352 class): every
    /// in-order canonical commit MUST be accepted — a `ParentHashMismatch`/error
    /// on a legitimate catch-up commit is a spurious rejection. After catch-up the
    /// member must converge (same tree) with a peer at its epoch. Sound because
    /// the backlog is the single canonical chain (no fork).
    pub fn catchup(&mut self) {
        let Some(late) = self.excluded.take() else {
            return;
        };
        let backlog = std::mem::take(&mut self.backlog);
        for (i, msg) in backlog.iter().enumerate() {
            match self.deliver_report(late as u8, msg) {
                RecvKind::Commit | RecvKind::Proposal => {}
                RecvKind::Err(e) => panic!(
                    "CATCH-UP REJECTION (cf. mls-rs #352): member {late} rejected canonical \
                     in-order commit #{i}/{} during catch-up: {e}",
                    backlog.len()
                ),
                other => panic!(
                    "CATCH-UP: member {late} got unexpected {other:?} for canonical commit \
                     #{i}/{}",
                    backlog.len()
                ),
            }
        }
        // After a full in-order catch-up, `late` must agree with a peer at its epoch.
        if let Some(late_tree) = self.tree_bytes_of(late) {
            let late_epoch = self.epoch_of(late);
            for &m in &self.active {
                if m != late && self.epoch_of(m) == late_epoch {
                    if let Some(peer_tree) = self.tree_bytes_of(m) {
                        assert_eq!(
                            late_tree, peer_tree,
                            "CATCH-UP divergence: member {late} and peer {m} at the same epoch \
                             have different trees after in-order catch-up"
                        );
                        break;
                    }
                }
            }
        }
    }

    /// Liveness / agreement oracle (targets mls-rs #352): after a *reliable
    /// broadcast* (all commits delivered to everyone, no drops), every active
    /// member must agree on (epoch, roster, tree shape). If a member fell behind,
    /// a legitimate commit it received was wrongly rejected — e.g. a spurious
    /// `ParentHashMismatch` from the `different_unmerged` blank-ancestor bug.
    ///
    /// This is sound only when called after `deliver_all()` in a no-drop scenario
    /// (the `mls_liveness` target), where members are never legitimately behind.
    pub fn assert_all_converged(&self) {
        if self.active.len() < 2 {
            return;
        }
        let mut reference: Option<(u64, usize, Vec<u8>)> = None;
        for &m in &self.active {
            let Some(epoch) = self.epoch_of(m) else {
                continue;
            };
            let roster = self.roster_len_of(m).unwrap_or(0);
            let tree = self.tree_bytes_of(m).unwrap_or_default();
            match &reference {
                None => reference = Some((epoch, roster, tree)),
                Some((re, rr, rtree)) => assert!(
                    epoch == *re && roster == *rr && &tree == rtree,
                    "LIVENESS/AGREEMENT violation (cf. mls-rs #352 and the broader \
                     tree-validation bug class): member {m} at (epoch {epoch}, roster {roster}, \
                     tree {} bytes) disagrees with (epoch {re}, roster {rr}, tree {} bytes) after \
                     reliable broadcast — a legitimate commit was rejected, or members diverged on \
                     tree state (parent/tree-hash or unmerged-leaf mishandling)",
                    tree.len(),
                    rtree.len()
                ),
            }
        }
    }

    /// Phase-2 ratchet-tree security oracle: detect leaf-index reuse sender
    /// aliasing (mls-rs #361). For any freed leaf now re-occupied by a *different*
    /// member, replaying the removed member's pre-removal message must NOT be
    /// accepted and attributed to that leaf — a patched library returns a
    /// `MemberNotFound`-class error because the signing identity at the leaf
    /// changed. Acceptance is a sender-spoofing bug.
    pub fn check_sender_integrity(&mut self) {
        let mut i = 0;
        while i < self.tombstones.len() {
            let leaf = self.tombstones[i].0;
            // Is the freed leaf now occupied by some active member?
            let reused = self
                .active
                .iter()
                .any(|&m| self.leaf_of[m].map(|l| *l) == Some(leaf));
            if !reused {
                i += 1;
                continue;
            }
            // Deliver the removed member's old message to an active member that
            // does NOT occupy the reused leaf, and inspect the attributed sender.
            let receiver = self
                .active
                .iter()
                .copied()
                .find(|&m| self.leaf_of[m].map(|l| *l) != Some(leaf));
            let msg = self.tombstones[i].1.clone();
            if let Some(receiver) = receiver {
                if let RecvKind::App { sender, .. } = self.deliver_report(receiver as u8, &msg) {
                    assert_ne!(
                        sender, leaf,
                        "SENDER ALIASING (mls-rs #361): a removed member's message was accepted \
                         and attributed to leaf {leaf}, now occupied by a different member"
                    );
                }
            }
            // One-shot per leaf: drop the tombstone after the reuse check.
            self.tombstones.remove(i);
        }
    }

    /// Encrypt an application message from client `idx` (no membership check).
    fn encrypt_for(&mut self, idx: usize, payload: &[u8]) -> Option<MlsMessage> {
        let g = self.groups[idx].as_mut()?;
        self.rt
            .block_on(async { g.encrypt_message(Default::default(), payload).await.ok() })
    }

    /// `sender` encrypts an application message; queued for delivery.
    pub fn encrypt(&mut self, sender_raw: u8, payload: &[u8]) {
        let sender = self.norm(sender_raw);
        if !self.active.contains(&sender) {
            return;
        }
        let payload = payload.to_vec();
        if let Some(m) = self.encrypt_for(sender, &payload) {
            self.pending.push(QueuedMsg { sender, msg: m });
        }
    }

    /// Apply one queued message to one member (swallows expected MLS errors).
    /// If `member` is the temporarily-excluded ("offline") member, the message is
    /// withheld into `backlog` in canonical order instead of delivered.
    fn deliver_to(&mut self, member: usize, msg: &MlsMessage) {
        if self.excluded == Some(member) {
            self.backlog.push(msg.clone());
            return;
        }
        if let Some(g) = self.groups[member].as_mut() {
            let _ = self
                .rt
                .block_on(async { g.decrypt_message(msg.clone()).await });
        }
    }

    pub fn deliver_next(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        let qm = self.pending.remove(0);
        for &m in self.active.clone().iter() {
            if m == qm.sender {
                continue;
            }
            self.deliver_to(m, &qm.msg);
        }
        self.history.push(qm);
    }

    pub fn deliver_all(&mut self) {
        while !self.pending.is_empty() {
            self.deliver_next();
        }
    }

    pub fn drop_next(&mut self) {
        if !self.pending.is_empty() {
            self.pending.remove(0);
        }
    }

    pub fn replay_old(&mut self, idx_raw: u8) {
        if self.history.is_empty() {
            return;
        }
        let idx = (idx_raw as usize) % self.history.len();
        let qm = self.history[idx].clone();
        for &m in self.active.clone().iter() {
            if m == qm.sender {
                continue;
            }
            self.deliver_to(m, &qm.msg);
        }
    }

    pub fn reorder_queue(&mut self) {
        self.pending.reverse();
    }

    /// Flip one byte of a queued message (corruption). If the mutated bytes no
    /// longer decode to an `MlsMessage`, the queued message is left unchanged.
    pub fn corrupt_queued(&mut self, idx_raw: u8, byte_idx: u16, value: u8) {
        if self.pending.is_empty() {
            return;
        }
        let idx = (idx_raw as usize) % self.pending.len();
        let Ok(mut bytes) = self.pending[idx].msg.mls_encode_to_vec() else {
            return;
        };
        if bytes.is_empty() {
            return;
        }
        let bi = (byte_idx as usize) % bytes.len();
        bytes[bi] ^= value;
        if let Ok(decoded) = MlsMessage::mls_decode(&mut &bytes[..]) {
            self.pending[idx].msg = decoded;
        }
    }

    /// Epoch of an active member's group (for invariant checks).
    pub fn epoch_of(&self, member: usize) -> Option<u64> {
        let g = self.groups[member].as_ref()?;
        Some(*self.rt.block_on(async { g.epoch() }))
    }

    /// Roster size of an active member's group.
    pub fn roster_len_of(&self, member: usize) -> Option<usize> {
        let g = self.groups[member].as_ref()?;
        Some(self.rt.block_on(async { g.roster().count() }))
    }

    /// Full serialized public ratchet tree of a member's group — node public
    /// keys, **parent hashes**, and **unmerged leaves**. This is the strongest
    /// cross-member agreement fingerprint: in correct MLS every member at a given
    /// epoch has a byte-identical tree, so comparing it catches the *whole class*
    /// of tree-state bugs (parent/tree-hash, unmerged-leaf handling — e.g. #352),
    /// not just one known issue. Roster/leaf-set comparison is strictly weaker.
    pub fn tree_bytes_of(&self, member: usize) -> Option<Vec<u8>> {
        let g = self.groups[member].as_ref()?;
        group_tree_bytes(g)
    }

    /// The raw leaf index a member occupies in the group, if any.
    pub fn leaf_u32(&self, member_raw: u8) -> Option<u32> {
        let m = self.norm(member_raw);
        self.leaf_of[m].map(|l| *l)
    }

    /// Encrypt an application message and RETURN it (instead of queuing) so the
    /// caller controls when/where it is (re)delivered. Used by the leaf-reuse
    /// sender-aliasing checks (mls-rs PR #361).
    pub fn encrypt_capture(&mut self, sender_raw: u8, payload: &[u8]) -> Option<MlsMessage> {
        let sender = self.norm(sender_raw);
        if !self.active.contains(&sender) {
            return None;
        }
        let payload = payload.to_vec();
        self.encrypt_for(sender, &payload)
    }

    /// Deliver a message to one member and report what the decoder produced
    /// (including the attributed sender leaf for application messages).
    pub fn deliver_report(&mut self, member_raw: u8, msg: &MlsMessage) -> RecvKind {
        let member = self.norm(member_raw);
        let Some(g) = self.groups[member].as_mut() else {
            return RecvKind::Err("no group".into());
        };
        self.rt.block_on(async {
            match g.decrypt_message(msg.clone()).await {
                Ok((
                    ReceivedMessage::ApplicationMessage {
                        sender, content, ..
                    },
                    _,
                )) => RecvKind::App {
                    sender: *sender,
                    len: content.len(),
                },
                Ok((ReceivedMessage::Commit { .. }, _)) => RecvKind::Commit,
                Ok((ReceivedMessage::Proposal, _)) => RecvKind::Proposal,
                Ok(_) => RecvKind::Other,
                Err(e) => RecvKind::Err(e.to_string()),
            }
        })
    }

    /// Persist `member`'s group to its kv, then reload it from storage and assert
    /// the reloaded state matches (epoch + roster). This exercises the meet-mls
    /// `MemKv` serde persistence path and catches "reload changes/loses state".
    pub fn reload(&mut self, member_raw: u8) {
        if self.active.is_empty() {
            return;
        }
        let member = self.norm(member_raw);
        if !self.active.contains(&member) {
            return;
        }

        // Snapshot live state (epoch + roster + tree shape) before persisting.
        let pre_epoch = self.epoch_of(member);
        let pre_roster = self.roster_len_of(member);
        let pre_tree = self.groups[member].as_ref().and_then(group_tree_bytes);

        // Persist the live group (mutable borrow of `groups` only).
        if let Some(g) = self.groups[member].as_mut() {
            let _ = self.rt.block_on(async { g.write_to_storage().await });
        }

        // Reload from storage (immutable borrows of `clients` + `store_kv`).
        let reloaded = {
            let client = &self.clients[member];
            let kv = &self.store_kv[member];
            self.rt.block_on(async {
                let entities: Vec<MlsGroupEntity> = kv.get_all().await.ok()?;
                let ent = entities.into_iter().next()?;
                client.load_group(&ent).await.ok()
            })
        };

        if let Some(g) = reloaded {
            let post_epoch = Some(*self.rt.block_on(async { g.epoch() }));
            let post_roster = Some(self.rt.block_on(async { g.roster().count() }));
            let post_tree = group_tree_bytes(&g);
            assert_eq!(
                pre_epoch, post_epoch,
                "reload changed epoch for member {member}: {pre_epoch:?} -> {post_epoch:?}"
            );
            assert_eq!(
                pre_roster, post_roster,
                "reload changed roster for member {member}: {pre_roster:?} -> {post_roster:?}"
            );
            assert_eq!(
                pre_tree,
                post_tree,
                "reload changed the ratchet tree for member {member} (pre {} vs post {} bytes)",
                pre_tree.as_ref().map_or(0, Vec::len),
                post_tree.as_ref().map_or(0, Vec::len)
            );
            let leaf = self.rt.block_on(async { g.own_leaf_index().ok() });
            self.groups[member] = Some(g);
            self.leaf_of[member] = leaf;
        }
    }
}

/// Full serialized public ratchet tree (the strong agreement fingerprint).
fn group_tree_bytes(g: &MlsGroup<MemKv>) -> Option<Vec<u8>> {
    g.ratchet_tree().to_bytes().ok()
}

/// Build one initialized MLS client. Mirrors `meet-core`'s
/// `create_initialized_client` test helper but uses only the light crates.
async fn build_client(email: &str, is_host: bool, meeting_id: &str) -> (MlsClient<MemKv>, MemKv) {
    let (client, _sig_pk) = MlsClient::new(MemKv::new(), MlsClientConfig::default())
        .await
        .expect("client::new");
    let holder_pem = client
        .get_holder_confirmation_key_pem()
        .expect("holder confirmation key");
    let (sd_cwt, issuer_sk) = mock_issuance(&holder_pem, meeting_id, email, is_host);
    let cks = CoseKeySet::new(&issuer_sk).expect("issuer cks");
    let store_kv = MemKv::new();
    let client = client
        .initialize(store_kv.clone(), sd_cwt, &cks, &cks)
        .expect("client initialize");
    (client, store_kv)
}

/// Replica of `meet-core`'s `mock_sdcwt_issuance` test helper.
fn mock_issuance(
    holder_confirmation_key_pem: &str,
    meeting_id: &str,
    email: &str,
    is_host: bool,
) -> (SdCwt, SigningKey) {
    let payload = ProtonMeetClaims {
        meeting_id: meeting_id.to_owned(),
        uuid: uuid::Uuid::new_v4().into_bytes(),
        oidc_claims: SpiceOidcClaims::default(),
        role: Role::User,
        mimi_provider: MimiProvider::ProtonAg,
        is_from_server: false,
        is_host,
        client_type: ClientType::Guest,
    };

    let issuer_signing_key = SigningKey::from_pkcs8_pem(ISSUER_SK_PEM).expect("issuer pkcs8");
    let issuer = Ed25519Issuer::new(issuer_signing_key.clone());

    let holder_vk =
        VerifyingKey::from_public_key_pem(holder_confirmation_key_pem).expect("holder vk pem");
    let holder_confirmation_key = (&holder_vk).try_into().expect("holder confirmation key");

    let device_id =
        cose_key_thumbprint::CoseKeyThumbprint::<32>::compute::<sha2::Sha256>(&holder_vk)
            .expect("thumbprint")
            .to_string();
    let sub = format!("mimi://meet.proton.me/d/{email}/{device_id}");

    let params = IssuerParams {
        protected_claims: None,
        unprotected_claims: None,
        payload: Some(payload),
        subject: Some(&sub),
        audience: None,
        expiry: None,
        with_not_before: true,
        with_issued_at: true,
        cti: None,
        cnonce: None,
        key_location: "https://auth.proton.me/issuer.cwk",
        holder_confirmation_key,
        issuer: "mimi://i/proton.me",
        leeway: Default::default(),
    };

    let sd_cwt = issuer
        .issue_cwt(&mut rand::thread_rng(), params)
        .expect("issue cwt");
    (sd_cwt, issuer_signing_key)
}

//! The `arbitrary`-driven operation model. One fuzz input decodes into a
//! `Scenario` (a bounded sequence of `Op`s) that the harness replays against a
//! fresh `TestMlsEnv`.
//!
//! Member indices are raw `u8`s; the env normalizes them modulo the client
//! count, so libFuzzer never has to "guess" a valid index.
use arbitrary::Arbitrary;

/// A complete MLS scenario: a bounded list of operations.
#[derive(Debug, Clone, Arbitrary)]
pub struct Scenario {
    pub ops: Vec<Op>,
}

#[derive(Debug, Clone, Arbitrary)]
pub enum Op {
    /// A non-member joins the group via an external commit, then the commit is
    /// delivered to all current members.
    Join { joiner: u8 },
    /// An existing member `adder` adds a non-member `addee` via an Add proposal
    /// commit (creating an *unmerged leaf*), and `addee` joins via the welcome.
    /// This is the path that produces `unmerged_leaves` — required to reach the
    /// mls-rs #352 blank-ancestor parent-hash bug.
    Add { adder: u8, addee: u8 },
    /// A member commits a self-`Update` (PCS key rotation) and delivers it.
    Update { member: u8 },
    /// A member commits its own removal (leave) and delivers it.
    Leave { member: u8 },
    /// A member encrypts an application message, queued for delivery.
    Encrypt { sender: u8, payload: Vec<u8> },
    /// Deliver the next queued message to all members except its sender.
    DeliverNext,
    /// Deliver every queued message, in order.
    DeliverAll,
    /// Drop the next queued message without delivering it.
    DropNext,
    /// Re-deliver a previously-delivered message (replay).
    ReplayOld { msg_index: u8 },
    /// Reverse the pending delivery queue (reorder).
    ReorderQueue,
    /// Flip a single byte of a queued message before it is delivered (corrupt).
    CorruptQueued {
        msg_index: u8,
        byte_index: u16,
        value: u8,
    },
    /// Persist a member's group and reload it from storage, asserting its state
    /// (epoch + roster + tree shape) is unchanged across the round-trip.
    ReloadStore { member: u8 },
}

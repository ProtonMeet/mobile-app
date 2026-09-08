//! Wrappers for [`std`] and [`tokio`] locking primitives.
//!
//! These wrappers should always be used instead of the locking primitives from
//! these crates. Synchronous ones should be preferred to their asynchronous
//! counterparts.

use std::{
    fmt::Debug,
    marker::PhantomData,
    ops::{Deref, DerefMut},
};

/// A wrapper around [`std::sync::RwLock`] that automatically recovers from poisoned locks.
///
/// When a thread attempts to lock (either in read or write mode) a poisoned [`SyncRwLock`],
/// the locking function will first use the function given to [`new`][Self::new] to
/// clean the value, then returning the guard to the value in its valid state.
pub struct SyncRwLock<T: ?Sized> {
    recover: Box<dyn Fn(&mut T) + Send + Sync>,
    lock: std::sync::RwLock<T>,
}

impl<T> SyncRwLock<T> {
    /// Creates a [`SyncRwLock`] from an initial value and a function used to recover
    /// poisoned values.
    pub fn new<F: Fn(&mut T) + 'static + Send + Sync>(value: T, recover: F) -> Self {
        Self {
            lock: std::sync::RwLock::new(value),
            recover: Box::new(recover),
        }
    }
}

impl<T: ?Sized> SyncRwLock<T> {
    /// Returns a read guard similarly to [std::sync::RwLock::read], but cleaning the value
    /// first if it is poisoned.
    ///
    /// Note that to clean the value, this function will have to acquire a write lock on the underlying
    /// `RwLock`, hence:
    /// - This will cause a deadlock or panic if the current thread is already holding a read lock.
    /// - It may increase contention when recovering from a panic.
    pub fn read(&self) -> std::sync::RwLockReadGuard<'_, T> {
        if let Ok(guard) = self.lock.read() {
            return guard;
        }

        std::sync::RwLockWriteGuard::downgrade(self.write())
    }

    /// Returns a write guard similarly to [std::sync::RwLock::write], but cleaning the value
    /// first if it is poisoned.
    pub fn write(&self) -> std::sync::RwLockWriteGuard<'_, T> {
        match self.lock.write() {
            Ok(guard) => guard,
            Err(e) => {
                let mut guard = e.into_inner();
                (self.recover)(&mut guard);
                self.lock.clear_poison();
                guard
            }
        }
    }

    /// Similar to [`Self::read`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_read(&self) -> Option<std::sync::RwLockReadGuard<'_, T>> {
        match self.lock.try_read() {
            Ok(guard) => return Some(guard),
            Err(std::sync::TryLockError::WouldBlock) => return None,
            _ => {}
        };

        self.try_write().map(std::sync::RwLockWriteGuard::downgrade)
    }

    /// Similar to [`Self::write`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_write(&self) -> Option<std::sync::RwLockWriteGuard<'_, T>> {
        match self.lock.try_write() {
            Ok(guard) => Some(guard),
            Err(std::sync::TryLockError::WouldBlock) => None,
            Err(std::sync::TryLockError::Poisoned(e)) => {
                let mut guard = e.into_inner();
                (self.recover)(&mut guard);
                self.lock.clear_poison();
                Some(guard)
            }
        }
    }
}

impl<T: ?Sized + Debug> Debug for SyncRwLock<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("SyncRwLock").field(&&self.lock).finish()
    }
}

/// A wrapper around [`std::sync::Mutex`] that automatically recovers from poisoned locks.
///
/// When a thread attempts to lock a poisoned [`SyncMutex`], the locking function will first
/// use the function given to [`new`][Self::new] to clean the value, then returning
/// the guard to the value in its valid state.
pub struct SyncMutex<T: ?Sized> {
    recover: Box<dyn Fn(&mut T) + Send + Sync>,
    lock: std::sync::Mutex<T>,
}

impl<T> SyncMutex<T> {
    /// Creates a [`SyncMutex`] from an initial value and a function used to recover
    /// poisoned values.
    pub fn new<F: Fn(&mut T) + 'static + Send + Sync>(value: T, recover: F) -> Self {
        Self {
            lock: std::sync::Mutex::new(value),
            recover: Box::new(recover),
        }
    }
}

impl<T: ?Sized> SyncMutex<T> {
    /// Returns a guard similarly to [std::sync::Mutex::lock], but cleaning the value
    /// first if it is poisoned.
    pub fn lock(&self) -> std::sync::MutexGuard<'_, T> {
        match self.lock.lock() {
            Ok(guard) => guard,
            Err(e) => {
                let mut guard = e.into_inner();
                (self.recover)(&mut guard);
                self.lock.clear_poison();
                guard
            }
        }
    }

    /// Similar to [`Self::lock`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_lock(&self) -> Option<std::sync::MutexGuard<'_, T>> {
        match self.lock.try_lock() {
            Ok(guard) => Some(guard),
            Err(std::sync::TryLockError::WouldBlock) => None,
            Err(std::sync::TryLockError::Poisoned(e)) => {
                let mut guard = e.into_inner();
                (self.recover)(&mut guard);
                self.lock.clear_poison();
                Some(guard)
            }
        }
    }
}

impl<T: ?Sized + Debug> Debug for SyncMutex<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("SyncMutex").field(&&self.lock).finish()
    }
}

/// A wrapper around [`tokio::sync::RwLock`].
///
/// Explicitly expose two set of locking functions:
/// - [`read`][Self::read] and [`write`][Self::write], returning guards wrapped in [`NotSend`].
/// - [`read_send`][Self::read_send] and [`write_send`][Self::write_send], returning usual guards.
///
/// The formers should be preferred as sending guards across threads can easily lead to unpredictable deadlocks.
#[derive(Default, Debug)]
pub struct AsyncRwLock<T: ?Sized>(tokio::sync::RwLock<T>);

impl<T> AsyncRwLock<T> {
    /// See [`tokio::sync::RwLock::new`].
    pub fn new(value: T) -> Self {
        Self(tokio::sync::RwLock::new(value))
    }
}

impl<T: ?Sized> AsyncRwLock<T> {
    /// Returns a guard from [`tokio::sync::RwLock::read`] wrapped in [`NotSend`], ensuring it cannot be sent to
    /// another thread (hence not kept across an `await` point[^note]). This should always be preferred to
    /// [`read_send`][Self::read_send].
    ///
    /// [^note]: This is technically not true for WASM and future ran through [`tokio::task::spawn_local`], but
    ///     since code is shared with a classic native target, it will have the expected behavior.
    ///
    /// ```compile_fail
    /// # use proton_meet_core::utils::sync::*;
    /// # fn main() {
    /// #     tokio::spawn(test());
    /// # }
    /// # async fn do_smth() {}
    /// async fn test() {
    ///     let rw = AsyncRwLock::new(());
    ///     let guard = rw.read().await;
    ///
    ///     do_smth().await;
    ///
    ///     dbg!(&*guard);
    /// }
    /// ```
    pub async fn read(&self) -> NotSend<tokio::sync::RwLockReadGuard<'_, T>> {
        NotSend(self.0.read().await, PhantomData)
    }
    /// Returns a guard from [`tokio::sync::RwLock::write`] wrapped in [`NotSend`], ensuring it cannot be sent to
    /// another thread (hence not kept across an `await` point[^note]). This should always be preferred to
    /// [`write_send`][Self::write_send].
    ///
    /// [^note]: This is technically not true for WASM and future ran through [`tokio::task::spawn_local`], but
    ///     since code is shared with a classic native target, it will have the expected behavior.
    ///
    /// ```compile_fail
    /// # use proton_meet_core::utils::sync::*;
    /// # fn main() {
    /// #     tokio::spawn(test());
    /// # }
    /// # async fn do_smth() {}
    /// async fn test() {
    ///     let rw = AsyncRwLock::new(());
    ///     let mut guard = rw.write().await;
    ///
    ///     do_smth().await;
    ///
    ///     *guard = ();
    /// }
    /// ```
    pub async fn write(&self) -> NotSend<tokio::sync::RwLockWriteGuard<'_, T>> {
        NotSend(self.0.write().await, PhantomData)
    }

    /// See [`tokio::sync::RwLock::read`]. [`Self::read`] should always be preferred.
    pub async fn read_send(&self) -> tokio::sync::RwLockReadGuard<'_, T> {
        self.0.read().await
    }
    /// See [`tokio::sync::RwLock::write`]. [`Self::write`] should always be preferred.
    pub async fn write_send(&self) -> tokio::sync::RwLockWriteGuard<'_, T> {
        self.0.write().await
    }

    /// Similar to [`Self::read`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_read(&self) -> Option<NotSend<tokio::sync::RwLockReadGuard<'_, T>>> {
        self.0.try_read().ok().map(|v| NotSend(v, PhantomData))
    }
    /// Similar to [`Self::write`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_write(&self) -> Option<NotSend<tokio::sync::RwLockWriteGuard<'_, T>>> {
        self.0.try_write().ok().map(|v| NotSend(v, PhantomData))
    }
    /// Similar to [`Self::read_send`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_read_send(&self) -> Option<tokio::sync::RwLockReadGuard<'_, T>> {
        self.0.try_read().ok()
    }
    /// Similar to [`Self::write_send`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_write_send(&self) -> Option<tokio::sync::RwLockWriteGuard<'_, T>> {
        self.0.try_write().ok()
    }
}

/// A wrapper around [`tokio::sync::Mutex`].
///
/// Explicitly expose two set of functions:
/// - [`lock`][Self::lock] returning a guard wrapped in [`NotSend`].
/// - [`lock_send`][Self::lock_send] returning the usual guard.
///
/// The former should be preferred as sending guards across threads can easily lead to unpredictable deadlocks.
#[derive(Default, Debug)]
pub struct AsyncMutex<T: ?Sized>(tokio::sync::Mutex<T>);

impl<T> AsyncMutex<T> {
    /// See [`tokio::sync::Mutex::new`].
    pub fn new(value: T) -> Self {
        Self(tokio::sync::Mutex::new(value))
    }
}

impl<T: ?Sized> AsyncMutex<T> {
    /// Returns a guard from [`tokio::sync::Mutex::lock`] wrapped in [`NotSend`], ensuring it cannot be sent to
    /// another thread (hence not kept across an `await` point[^note]). This should always be preferred to
    /// [`lock_send`][Self::lock_send].
    ///
    /// [^note]: This is technically not true for WASM and future ran through [`tokio::task::spawn_local`], but
    ///     since code is shared with a classic native target, it will have the expected behavior.
    ///     
    /// ```compile_fail
    /// # use proton_meet_core::utils::sync::*;
    /// # fn main() {
    /// #     tokio::spawn(test());
    /// # }
    /// # async fn do_smth() {}
    /// async fn test() {
    ///     let rw = AsyncMutex::new(());
    ///     let mut guard = rw.lock().await;
    ///
    ///     do_smth().await;
    ///
    ///     *guard = ();
    /// }
    /// ```
    pub async fn lock(&self) -> NotSend<tokio::sync::MutexGuard<'_, T>> {
        NotSend(self.0.lock().await, PhantomData)
    }

    /// See [`tokio::sync::Mutex::lock`]. [`Self::lock`] should always be preferred.
    pub async fn lock_send(&self) -> tokio::sync::MutexGuard<'_, T> {
        self.0.lock().await
    }

    /// Similar to [`Self::lock`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_lock(&self) -> Option<NotSend<tokio::sync::MutexGuard<'_, T>>> {
        self.0.try_lock().ok().map(|v| NotSend(v, PhantomData))
    }
    /// Similar to [`Self::lock_send`], but returns `None` if it would block (i.e. someone else already
    /// acquired the lock).
    pub fn try_lock_send(&self) -> Option<tokio::sync::MutexGuard<'_, T>> {
        self.0.try_lock().ok()
    }
}
/// Transparent wrapper around any value forcing it to be [`!Send`][Send].
#[must_use]
pub struct NotSend<T>(
    T,
    /// Forces the type to be !Send.
    PhantomData<std::sync::MutexGuard<'static, ()>>,
);
impl<T: Deref> Deref for NotSend<T> {
    type Target = T::Target;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl<T: DerefMut> DerefMut for NotSend<T> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

#[cfg(test)]
mod test {
    use std::sync::Arc;

    use crate::utils::sync::{SyncMutex, SyncRwLock};

    #[test]
    fn rwlock_panic_read_recover() {
        let lock = Arc::new(SyncRwLock::new(0u8, |v| *v = 0));

        assert_eq!(*lock.read(), 0);

        *lock.write() += 1;
        *lock.write() += 1;

        assert_eq!(*lock.read(), 2);

        // Panic while holding a read lock, which does not poison. The value should stay unchanged.
        let lock_clone = lock.clone();
        #[allow(unused)]
        let thread = std::thread::spawn(move || {
            let mut guard = lock_clone.read();
            panic!();
            println!("{}", *guard);
        });
        let _ = thread.join();

        assert_eq!(*lock.read(), 2);
    }

    #[test]
    fn rwlock_panic_write_recover() {
        let lock = Arc::new(SyncRwLock::new(0u8, |v| *v = 0));

        assert_eq!(*lock.read(), 0);

        *lock.write() += 1;
        *lock.write() += 1;

        assert_eq!(*lock.read(), 2);

        // Panic while holding a write lock. The lock should clean it (setting it to 0) on the following
        // acquisition.
        let lock_clone = lock.clone();
        #[allow(unused)]
        let thread = std::thread::spawn(move || {
            let mut guard = lock_clone.write();
            panic!();
            *guard = 3;
        });
        let _ = thread.join();

        assert_eq!(*lock.read(), 0);
    }

    #[test]
    fn mutex_panic_recover() {
        let lock = Arc::new(SyncMutex::new(0u8, |v| *v = 0));

        assert_eq!(*lock.lock(), 0);

        *lock.lock() += 1;
        *lock.lock() += 1;

        assert_eq!(*lock.lock(), 2);

        // Panic while holding a lock. The lock should clean it (setting it to 0) on the following
        // acquisition.
        let lock_clone = lock.clone();
        #[allow(unused)]
        let thread = std::thread::spawn(move || {
            let mut guard = lock_clone.lock();
            panic!();
            *guard = 3;
        });
        let _ = thread.join();

        assert_eq!(*lock.lock(), 0);
    }
}

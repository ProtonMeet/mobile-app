// src/spawn.rs
use core::future::Future;

#[cfg(not(target_family = "wasm"))]
pub type SpawnHandle<T> = tokio::task::JoinHandle<T>;

#[cfg(target_family = "wasm")]
pub type SpawnHandle<T> = futures::future::RemoteHandle<T>;

/// Spawn a future on the platform's executor:
/// - Native: tokio::spawn (requires Send + 'static)
/// - WASM (browser): wasm_bindgen_futures::spawn_local
#[cfg(not(target_family = "wasm"))]
pub fn spawn<F>(fut: F) -> SpawnHandle<F::Output>
where
    F: Future + Send + 'static,
    F::Output: Send + 'static,
{
    tokio::spawn(fut)
}

#[cfg(target_family = "wasm")]
pub fn spawn<F>(fut: F) -> SpawnHandle<F::Output>
where
    F: Future + 'static,
{
    use futures::FutureExt;
    let (f, handle) = fut.remote_handle();
    wasm_bindgen_futures::spawn_local(f);
    handle
}

/// Fire-and-forget variant (Output = ()).
#[cfg(not(target_family = "wasm"))]
pub fn spawn_detached<F>(fut: F)
where
    F: Future<Output = ()> + Send + 'static,
{
    tokio::spawn(fut);
}

#[cfg(target_family = "wasm")]
pub fn spawn_detached<F>(fut: F)
where
    F: Future<Output = ()> + 'static,
{
    wasm_bindgen_futures::spawn_local(fut);
}

/// Result of selecting between two futures
pub enum SelectResult<A, B> {
    /// First future completed
    First(A),
    /// Second future completed
    Second(B),
}

/// Select between two futures:
/// - Native: uses tokio::select! macro internally
/// - WASM: uses futures::future::select
#[cfg(not(target_family = "wasm"))]
pub async fn select<F1, F2>(fut1: F1, fut2: F2) -> SelectResult<F1::Output, F2::Output>
where
    F1: Future,
    F2: Future,
{
    tokio::select! {
        result1 = fut1 => SelectResult::First(result1),
        result2 = fut2 => SelectResult::Second(result2),
    }
}

#[cfg(target_family = "wasm")]
pub async fn select<F1, F2>(fut1: F1, fut2: F2) -> SelectResult<F1::Output, F2::Output>
where
    F1: Future,
    F2: Future,
{
    use futures::future::select;
    let mut fut1 = Box::pin(fut1);
    let mut fut2 = Box::pin(fut2);
    match select(fut1.as_mut(), fut2.as_mut()).await {
        futures::future::Either::Left((result1, _)) => SelectResult::First(result1),
        futures::future::Either::Right((result2, _)) => SelectResult::Second(result2),
    }
}

/// Join two futures, waiting for both to complete:
/// - Native: uses tokio::join! macro internally
/// - WASM: uses futures::join! macro internally
#[cfg(not(target_family = "wasm"))]
pub async fn join<F1, F2>(fut1: F1, fut2: F2) -> (F1::Output, F2::Output)
where
    F1: Future,
    F2: Future,
{
    tokio::join!(fut1, fut2)
}

#[cfg(target_family = "wasm")]
pub async fn join<F1, F2>(fut1: F1, fut2: F2) -> (F1::Output, F2::Output)
where
    F1: Future,
    F2: Future,
{
    futures::join!(fut1, fut2)
}

/// Join three futures, waiting for all to complete:
/// - Native: uses tokio::join! macro internally
/// - WASM: uses futures::join! macro internally
#[cfg(not(target_family = "wasm"))]
pub async fn join3<F1, F2, F3>(fut1: F1, fut2: F2, fut3: F3) -> (F1::Output, F2::Output, F3::Output)
where
    F1: Future,
    F2: Future,
    F3: Future,
{
    tokio::join!(fut1, fut2, fut3)
}

#[cfg(target_family = "wasm")]
pub async fn join3<F1, F2, F3>(fut1: F1, fut2: F2, fut3: F3) -> (F1::Output, F2::Output, F3::Output)
where
    F1: Future,
    F2: Future,
    F3: Future,
{
    futures::join!(fut1, fut2, fut3)
}

/// Try join two futures that return Result, waiting for both to complete:
/// - Native: uses tokio::try_join! macro internally
/// - WASM: uses futures::try_join! macro internally
///   Short-circuits on the first error.
#[cfg(not(target_family = "wasm"))]
pub async fn try_join<F1, F2, T1, T2, E>(fut1: F1, fut2: F2) -> Result<(T1, T2), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
{
    tokio::try_join!(fut1, fut2)
}

#[cfg(target_family = "wasm")]
pub async fn try_join<F1, F2, T1, T2, E>(fut1: F1, fut2: F2) -> Result<(T1, T2), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
{
    futures::try_join!(fut1, fut2)
}

/// Try join three futures that return Result, waiting for all to complete:
/// - Native: uses tokio::try_join! macro internally
/// - WASM: uses futures::try_join! macro internally
///   Short-circuits on the first error.
#[cfg(not(target_family = "wasm"))]
pub async fn try_join3<F1, F2, F3, T1, T2, T3, E>(
    fut1: F1,
    fut2: F2,
    fut3: F3,
) -> Result<(T1, T2, T3), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
    F3: Future<Output = Result<T3, E>>,
{
    tokio::try_join!(fut1, fut2, fut3)
}

#[cfg(target_family = "wasm")]
pub async fn try_join3<F1, F2, F3, T1, T2, T3, E>(
    fut1: F1,
    fut2: F2,
    fut3: F3,
) -> Result<(T1, T2, T3), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
    F3: Future<Output = Result<T3, E>>,
{
    futures::try_join!(fut1, fut2, fut3)
}

/// Try join four futures that return Result, waiting for all to complete:
/// - Native: uses tokio::try_join! macro internally
/// - WASM: uses futures::try_join! macro internally
///   Short-circuits on the first error.
#[cfg(not(target_family = "wasm"))]
pub async fn try_join4<F1, F2, F3, F4, T1, T2, T3, T4, E>(
    fut1: F1,
    fut2: F2,
    fut3: F3,
    fut4: F4,
) -> Result<(T1, T2, T3, T4), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
    F3: Future<Output = Result<T3, E>>,
    F4: Future<Output = Result<T4, E>>,
{
    tokio::try_join!(fut1, fut2, fut3, fut4)
}

#[cfg(target_family = "wasm")]
pub async fn try_join4<F1, F2, F3, F4, T1, T2, T3, T4, E>(
    fut1: F1,
    fut2: F2,
    fut3: F3,
    fut4: F4,
) -> Result<(T1, T2, T3, T4), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
    F3: Future<Output = Result<T3, E>>,
    F4: Future<Output = Result<T4, E>>,
{
    futures::try_join!(fut1, fut2, fut3, fut4)
}

/// Try join five futures that return Result, waiting for all to complete:
/// - Native: uses tokio::try_join! macro internally
/// - WASM: uses futures::try_join! macro internally
///   Short-circuits on the first error.
#[cfg(not(target_family = "wasm"))]
pub async fn try_join5<F1, F2, F3, F4, F5, T1, T2, T3, T4, T5, E>(
    fut1: F1,
    fut2: F2,
    fut3: F3,
    fut4: F4,
    fut5: F5,
) -> Result<(T1, T2, T3, T4, T5), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
    F3: Future<Output = Result<T3, E>>,
    F4: Future<Output = Result<T4, E>>,
    F5: Future<Output = Result<T5, E>>,
{
    tokio::try_join!(fut1, fut2, fut3, fut4, fut5)
}

#[cfg(target_family = "wasm")]
pub async fn try_join5<F1, F2, F3, F4, F5, T1, T2, T3, T4, T5, E>(
    fut1: F1,
    fut2: F2,
    fut3: F3,
    fut4: F4,
    fut5: F5,
) -> Result<(T1, T2, T3, T4, T5), E>
where
    F1: Future<Output = Result<T1, E>>,
    F2: Future<Output = Result<T2, E>>,
    F3: Future<Output = Result<T3, E>>,
    F4: Future<Output = Result<T4, E>>,
    F5: Future<Output = Result<T5, E>>,
{
    futures::try_join!(fut1, fut2, fut3, fut4, fut5)
}

#[cfg(test)]
mod tests {
    use crate::utils;
    use proton_meet_macro::unified_test;

    #[cfg(all(test, target_family = "wasm"))]
    use wasm_bindgen_test::wasm_bindgen_test_configure;
    #[cfg(all(test, target_family = "wasm"))]
    wasm_bindgen_test_configure!(run_in_browser);
    // Helper: await wrapper to normalize handle behavior across targets
    async fn await_handle<T: 'static>(h: utils::spawn::SpawnHandle<T>) -> T {
        #[cfg(not(target_family = "wasm"))]
        {
            h.await.expect("task panicked")
        }

        #[cfg(target_family = "wasm")]
        {
            h.await
        }
    }

    // === Test 1: return value ===
    // Apply the correct test attribute per target:
    #[unified_test]
    async fn spawn_returns_value_on_all_targets() {
        let handle = utils::spawn(async { 21 + 21 });
        let v = await_handle(handle).await;
        assert_eq!(v, 42);
    }

    // === Test 2: detached ===
    #[unified_test]
    async fn spawn_detached_runs_on_all_targets() {
        // Use futures::channel so it works on both targets without tokio::time
        use futures::channel::oneshot;

        let (tx, rx) = oneshot::channel::<u8>();
        utils::spawn_detached(async move {
            let _ = tx.send(7);
        });

        let got = rx.await.expect("channel closed");
        assert_eq!(got, 7);
    }

    // === Test 3: select - first future completes ===
    #[unified_test]
    async fn select_first_future_completes() {
        use futures::channel::oneshot;

        let (tx1, rx1) = oneshot::channel::<u8>();
        let (_tx2, rx2) = oneshot::channel::<u8>();

        // Send value to first channel immediately
        let _ = tx1.send(42);

        match utils::select(rx1, rx2).await {
            utils::SelectResult::First(result) => {
                assert_eq!(result.expect("First channel should succeed"), 42);
            }
            utils::SelectResult::Second(_) => panic!("First future should complete first"),
        }
    }

    // === Test 4: select - second future completes ===
    #[unified_test]
    async fn select_second_future_completes() {
        use futures::channel::oneshot;

        let (_tx1, rx1) = oneshot::channel::<u8>();
        let (tx2, rx2) = oneshot::channel::<u8>();

        // Send value to second channel immediately
        let _ = tx2.send(99);

        match utils::select(rx1, rx2).await {
            utils::SelectResult::First(_) => panic!("Second future should complete first"),
            utils::SelectResult::Second(result) => {
                assert_eq!(result.expect("Second channel should succeed"), 99);
            }
        }
    }
}

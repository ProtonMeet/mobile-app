const COOKIE_ACK_TIMEOUT_MS = 5000;

let nextCookieRequestId = 1;
const pendingCookieRequests = new Map();

function replayCookie(messageType, cookie) {
  const id = nextCookieRequestId++;

  return new Promise((resolve, reject) => {
    const timeoutHandle = globalThis.setTimeout(() => {
      const pending = pendingCookieRequests.get(id);
      if (!pending) {
        return;
      }
      pendingCookieRequests.delete(id);
      pending.reject(
        new Error(
          `cookie replay timed out waiting for ack (id=${id}, type=${messageType})`,
        ),
      );
    }, COOKIE_ACK_TIMEOUT_MS);

    pendingCookieRequests.set(id, { resolve, reject, timeoutHandle });

    try {
      globalThis.postMessage({ type: messageType, id, cookie });
    } catch (error) {
      const pending = pendingCookieRequests.get(id);
      if (!pending) {
        return;
      }
      globalThis.clearTimeout(pending.timeoutHandle);
      pendingCookieRequests.delete(id);
      pending.reject(
        error instanceof Error
          ? error
          : new Error("failed to post cookie replay message"),
      );
    }
  });
}

globalThis.addEventListener("message", (event) => {
  const data = event?.data;
  if (!data || data.type !== "meet-core:cookie-ack" || typeof data.id !== "number") {
    return;
  }

  const pending = pendingCookieRequests.get(data.id);
  if (!pending) {
    return;
  }

  globalThis.clearTimeout(pending.timeoutHandle);
  pendingCookieRequests.delete(data.id);

  if (data.ok === true) {
    pending.resolve();
    return;
  }

  pending.reject(new Error(data.error ?? "cookie replay failed"));
});

export async function set_ws_auth_cookie_from_main(cookie) {
  await replayCookie("meet-core:set-ws-cookie", cookie);
}

export async function clear_ws_auth_cookie_from_main(cookie) {
  await replayCookie("meet-core:clear-ws-cookie", cookie);
}

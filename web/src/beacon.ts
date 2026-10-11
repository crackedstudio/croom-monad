/**
 * A drand client that survives one host being down.
 *
 * The reference SDK's `DrandClient` takes a base URL and a `fetch`. Rather than reimplement it,
 * this supplies a `fetch` that rewrites the host and retries across the public mirrors — so the
 * SDK's verification logic is untouched and only reachability changes.
 *
 * The beacon is the one dependency the chart genuinely cannot do without: no beacon, no prices.
 * The chain, by contrast, is optional — an outage there costs you the ability to *check* a
 * commitment, not the ability to compute the series. So this is the dependency worth hardening.
 */
import { DrandClient } from "./protocol.js";

/** Public evmnet endpoints. All free, all keyless, all serving the same signed rounds. */
export const DRAND_HOSTS = [
  "https://api.drand.sh/v2/beacons/evmnet",
  "https://api2.drand.sh/v2/beacons/evmnet",
  "https://api3.drand.sh/v2/beacons/evmnet",
] as const;

const TIMEOUT_MS = 9_000;

/** Which host answered last, so a healthy mirror is tried first next time. */
let preferred = 0;

async function once(url: string, init: RequestInit | undefined, signal: AbortSignal): Promise<Response> {
  return fetch(url, { ...init, signal });
}

/**
 * Tries each mirror in turn, starting from whichever answered last. A signature is a signature
 * wherever it came from — the SDK verifies it against the group public key regardless — so
 * failing over between hosts weakens nothing.
 */
export const failoverFetch: typeof fetch = async (input, init) => {
  const requested = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

  const base = DRAND_HOSTS.find((h) => requested.startsWith(h));
  if (!base) return fetch(input as never, init);
  const path = requested.slice(base.length);

  let lastError: unknown;
  for (let attempt = 0; attempt < DRAND_HOSTS.length; attempt++) {
    const index = (preferred + attempt) % DRAND_HOSTS.length;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    try {
      const response = await once(DRAND_HOSTS[index] + path, init, controller.signal);
      if (response.ok) {
        preferred = index;
        return response;
      }
      lastError = new Error(`${DRAND_HOSTS[index]}${path} → ${response.status}`);
    } catch (err) {
      lastError = err;
    } finally {
      clearTimeout(timer);
    }
  }
  throw new Error(
    `every drand mirror failed (${DRAND_HOSTS.length} tried): ${(lastError as Error)?.message ?? "unknown"}`,
  );
};

export const beacon = new DrandClient(DRAND_HOSTS[0], undefined, failoverFetch);

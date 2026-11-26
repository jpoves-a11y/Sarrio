/** Cifrado de los tokens de proveedores (Polar…) con AES-GCM y la clave `TOKEN_ENCRYPTION_KEY` (base64, 32 bytes). */

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const unb64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

async function key(secret: string): Promise<CryptoKey> {
  const raw = unb64(secret);
  if (raw.length !== 32) throw new Error("TOKEN_ENCRYPTION_KEY must be 32 bytes in base64");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Texto → `iv:cifrado`, ambos en base64. */
export async function encryptToken(plain: string, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await key(secret), new TextEncoder().encode(plain));
  return `${b64(iv)}:${b64(new Uint8Array(data))}`;
}

export async function decryptToken(stored: string, secret: string): Promise<string> {
  const [iv, data] = stored.split(":");
  if (!iv || !data) throw new Error("bad token format");
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(iv) }, await key(secret), unb64(data));
  return new TextDecoder().decode(plain);
}

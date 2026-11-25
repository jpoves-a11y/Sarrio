/** Identificador ordenable por tiempo (prefijo base36 de ms + aleatorio). */
export function newId(): string {
  const time = Date.now().toString(36).padStart(9, "0");
  const rand = crypto.getRandomValues(new Uint8Array(8));
  return time + [...rand].map((b) => b.toString(16).padStart(2, "0")).join("");
}

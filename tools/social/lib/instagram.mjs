// Publicar en Instagram (Content Publishing API). Necesita IG_USER_ID e IG_ACCESS_TOKEN
// (cuenta profesional; «Instagram API with Instagram Login», permiso instagram_business_content_publish).
//
// Instagram descarga los recursos desde una URL pública: por defecto, el archivo en la rama main
// de este repositorio (es público). MEDIA_BASE_URL permite cambiarlo.

const DEFAULT_MEDIA_BASE = "https://raw.githubusercontent.com/jpoves-a11y/Sarrio/main/marketing/queue";

export function mediaUrl(post, file, env = process.env) {
  const base = (env.MEDIA_BASE_URL || DEFAULT_MEDIA_BASE).replace(/\/$/, "");
  const day = post.id.split("/")[0];
  return `${base}/${encodeURIComponent(day)}/${encodeURIComponent(file)}`;
}

export async function publishInstagram(post, { env = process.env, fetchImpl = fetch, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) } = {}) {
  const { IG_USER_ID: user, IG_ACCESS_TOKEN: token } = env;
  if (!user || !token) throw new Error("faltan IG_USER_ID o IG_ACCESS_TOKEN");
  const graph = `https://${env.IG_GRAPH_HOST || "graph.instagram.com"}/${env.IG_GRAPH_VERSION || "v23.0"}`;

  const call = async (method, pathname, params = {}) => {
    const url = new URL(`${graph}/${pathname}`);
    const body = new URLSearchParams({ ...params, access_token: token });
    const res = method === "GET"
      ? await fetchImpl(`${url}?${body}`)
      : await fetchImpl(url, { method, body });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.error) throw new Error(`Instagram ${pathname}: ${res.status} ${data.error?.message ?? ""}`.trim());
    return data;
  };

  // Los contenedores tardan en procesarse (sobre todo el vídeo): esperamos a FINISHED.
  const waitReady = async (id) => {
    for (let i = 0; i < 60; i++) {
      const { status_code: status } = await call("GET", id, { fields: "status_code" });
      if (status === "FINISHED") return;
      if (status === "ERROR" || status === "EXPIRED") throw new Error(`Instagram: el contenedor ${id} acabó en ${status}`);
      await sleep(5000);
    }
    throw new Error(`Instagram: el contenedor ${id} no terminó de procesarse`);
  };

  const files = [].concat(post.meta.recursos ?? []);
  const caption = post.text;
  let container;
  if (post.meta.red === "instagram-imagen") {
    ({ id: container } = await call("POST", `${user}/media`, { image_url: mediaUrl(post, files[0], env), caption }));
  } else if (post.meta.red === "instagram-carrusel") {
    const children = [];
    for (const f of files) {
      const { id } = await call("POST", `${user}/media`, { image_url: mediaUrl(post, f, env), is_carousel_item: "true" });
      children.push(id);
    }
    for (const id of children) await waitReady(id);
    ({ id: container } = await call("POST", `${user}/media`, { media_type: "CAROUSEL", children: children.join(","), caption }));
  } else if (post.meta.red === "instagram-reel") {
    const params = { media_type: "REELS", video_url: mediaUrl(post, files[0], env), caption, share_to_feed: "true" };
    if (post.meta.portada) params.cover_url = mediaUrl(post, post.meta.portada, env);
    ({ id: container } = await call("POST", `${user}/media`, params));
  } else {
    throw new Error(`publishInstagram no sabe publicar ${post.meta.red}`);
  }
  await waitReady(container);
  const { id } = await call("POST", `${user}/media_publish`, { creation_id: container });
  const { permalink } = await call("GET", id, { fields: "permalink" }).catch(() => ({}));
  return { id, url: permalink ?? null };
}

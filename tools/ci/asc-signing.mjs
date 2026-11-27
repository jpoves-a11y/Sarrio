#!/usr/bin/env node
// Firma para TestFlight con la API de App Store Connect, sin la firma automática de Xcode
// (que falla con claves API en los runners: «Authentication failed … bearer token»).
//
//   node tools/ci/asc-signing.mjs prepare <csr.pem> <out-dir>
//     Crea un certificado de distribución temporal a partir del CSR, se asegura de que existen los
//     App IDs de la app y de la Share Extension y crea un perfil de App Store para cada uno.
//     Escribe en <out-dir>: cert.cer, app.mobileprovision, share.mobileprovision y signing.env
//     (CERT_ID, APP_PROFILE, SHARE_PROFILE) para el resto del workflow.
//   node tools/ci/asc-signing.mjs cleanup <cert-id>
//     Revoca el certificado temporal y borra los perfiles de CI (no afecta a las builds subidas).
//
// Variables: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID, GITHUB_RUN_NUMBER.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID, GITHUB_RUN_NUMBER = "local" } = process.env;
const API = "https://api.appstoreconnect.apple.com";
const PROFILE_PREFIX = "Sarrio CI";

function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64({ alg: "ES256", kid: ASC_KEY_ID.trim(), typ: "JWT" })}.${b64({ iss: ASC_ISSUER_ID.trim(), iat: now, exp: now + 900, aud: "appstoreconnect-v1" })}`;
  const sig = crypto.sign("sha256", Buffer.from(unsigned), { key: crypto.createPrivateKey(ASC_KEY_P8.trim()), dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${sig.toString("base64url")}`;
}

async function api(method, route, body) {
  const res = await fetch(API + route, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const detail = (json.errors ?? []).map((e) => `${e.title}: ${e.detail}`).join(" | ");
    throw new Error(`${method} ${route} → HTTP ${res.status} ${detail}`);
  }
  return json;
}

async function ensureBundleId(identifier, name) {
  const found = await api("GET", `/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=20`);
  const exact = found.data.find((b) => b.attributes.identifier === identifier);
  if (exact) return exact.id;
  console.log(`Registrando el App ID ${identifier}`);
  const created = await api("POST", "/v1/bundleIds", {
    data: { type: "bundleIds", attributes: { identifier, name, platform: "IOS" } },
  });
  return created.data.id;
}

/** Activa una capacidad en el App ID si no la tiene (las que ya tenga se dejan como están). */
async function ensureCapability(bundleId, capabilityType) {
  const caps = await api("GET", `/v1/bundleIds/${bundleId}/bundleIdCapabilities`);
  if (caps.data.some((c) => c.attributes.capabilityType === capabilityType)) return;
  try {
    await api("POST", "/v1/bundleIdCapabilities", {
      data: {
        type: "bundleIdCapabilities",
        attributes: { capabilityType },
        relationships: { bundleId: { data: { type: "bundleIds", id: bundleId } } },
      },
    });
    console.log(`Capacidad ${capabilityType} activada`);
  } catch (e) {
    console.log(`::warning::No se pudo activar ${capabilityType}: ${e.message}`);
  }
}

async function deleteCIProfiles() {
  const list = await api("GET", `/v1/profiles?filter[name]=${encodeURIComponent(PROFILE_PREFIX)}&limit=200`);
  for (const p of list.data.filter((p) => p.attributes.name.startsWith(PROFILE_PREFIX))) {
    await api("DELETE", `/v1/profiles/${p.id}`).catch(() => {});
  }
}

async function createProfile(name, bundleId, certId, outFile) {
  const created = await api("POST", "/v1/profiles", {
    data: {
      type: "profiles",
      attributes: { name, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundleId } },
        certificates: { data: [{ type: "certificates", id: certId }] },
      },
    },
  });
  fs.writeFileSync(outFile, Buffer.from(created.data.attributes.profileContent, "base64"));
  return created.data.attributes.name;
}

async function prepare(csrPath, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  const csr = fs.readFileSync(csrPath, "utf8").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");

  let cert;
  try {
    cert = await api("POST", "/v1/certificates", {
      data: { type: "certificates", attributes: { certificateType: "DISTRIBUTION", csrContent: csr } },
    });
  } catch (e) {
    if (/limit|maximum|already/i.test(e.message)) {
      throw new Error(
        `${e.message}\nHas llegado al máximo de certificados de distribución. Revoca uno que no uses en ` +
          "developer.apple.com → Certificates y vuelve a lanzar el workflow.",
      );
    }
    throw e;
  }
  const certId = cert.data.id;
  fs.writeFileSync(path.join(outDir, "cert.cer"), Buffer.from(cert.data.attributes.certificateContent, "base64"));

  const bundle = BUNDLE_ID.trim();
  const appId = await ensureBundleId(bundle, "Sarrio");
  const shareId = await ensureBundleId(`${bundle}.share`, "Sarrio Share");
  const liveId = await ensureBundleId(`${bundle}.live`, "Sarrio Live");
  for (const cap of ["HEALTHKIT", "SIGN_IN_WITH_APPLE", "PUSH_NOTIFICATIONS", "APP_GROUPS"]) await ensureCapability(appId, cap);
  await ensureCapability(shareId, "APP_GROUPS");

  await deleteCIProfiles();
  const appProfile = await createProfile(`${PROFILE_PREFIX} ${GITHUB_RUN_NUMBER} app`, appId, certId, path.join(outDir, "app.mobileprovision"));
  const shareProfile = await createProfile(`${PROFILE_PREFIX} ${GITHUB_RUN_NUMBER} share`, shareId, certId, path.join(outDir, "share.mobileprovision"));
  const liveProfile = await createProfile(`${PROFILE_PREFIX} ${GITHUB_RUN_NUMBER} live`, liveId, certId, path.join(outDir, "live.mobileprovision"));

  fs.writeFileSync(path.join(outDir, "signing.env"), `CERT_ID=${certId}\nAPP_PROFILE=${appProfile}\nSHARE_PROFILE=${shareProfile}\nLIVE_PROFILE=${liveProfile}\n`);
  console.log(`Certificado temporal y perfiles listos: «${appProfile}», «${shareProfile}»`);
}

async function cleanup(certId) {
  if (certId) await api("DELETE", `/v1/certificates/${certId}`).catch((e) => console.log(`::warning::${e.message}`));
  await deleteCIProfiles();
  console.log("Certificado temporal revocado y perfiles de CI borrados");
}

const [command, a, b] = process.argv.slice(2);
try {
  if (command === "prepare") await prepare(a, b);
  else if (command === "cleanup") await cleanup(a);
  else throw new Error("Uso: asc-signing.mjs prepare <csr> <dir> | cleanup <cert-id>");
} catch (e) {
  console.error(`::error::${e.message}`);
  process.exit(1);
}

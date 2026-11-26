import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { peakMeta, peaks } from "../src/db/schema";

describe("/v1/peaks", () => {
  it("serves a cell pack and the dataset version", async () => {
    const t = await createTestApp();
    await t.db.insert(peaks).values({ id: 1, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w", range: "Pirineos" });
    const pack = (await (await t.request("GET", "/v1/peaks/pack/sp86")).json()) as any;
    expect(pack.peaks.map((p: any) => p.name)).toEqual(["Aneto"]);
    expect(pack.peaks[0].range).toBe("Pirineos");

    expect(((await (await t.request("GET", "/v1/peaks/version")).json()) as any).version).toBeNull();
    await t.db.insert(peakMeta).values({ key: "dataset_version", value: "1784000000000" });
    expect(((await (await t.request("GET", "/v1/peaks/version")).json()) as any).version).toBe(1784000000000);
  });
});

describe("GET /v1/peaks/search", () => {
  it("finds peaks by name, highest first", async () => {
    const t = await createTestApp();
    await t.db.insert(peaks).values([
      { id: 1, name: "Punta Nera", ele: 3064, lat: 45.58, lon: 7.46, geohash: "u0hmq", range: "Alpes" },
      { id: 2, name: "Punta Nera della Grivola", ele: 3683, lat: 45.58, lon: 7.26, geohash: "u0j2b", range: "Alpes" },
      { id: 3, name: "Aneto", nameEs: "Aneto", ele: 3404, lat: 42.63, lon: 0.65, geohash: "sp86w" },
    ]);
    const res = (await (await t.request("GET", "/v1/peaks/search?q=nera")).json()) as any;
    expect(res.peaks.map((p: any) => p.id)).toEqual([2, 1]);
    expect(((await (await t.request("GET", "/v1/peaks/search?q=nera&limit=1")).json()) as any).peaks).toHaveLength(1);
    expect((await t.request("GET", "/v1/peaks/search?q=a")).status).toBe(400);
    // Los comodines de LIKE se quitan: «ne%ra» busca «nera»
    expect(((await (await t.request("GET", "/v1/peaks/search?q=ne%25ra")).json()) as any).peaks).toHaveLength(2);
  });
});

import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { peakMeta, peaks } from "../src/db/schema";

describe("/v1/peaks", () => {
  it("serves a cell pack and the dataset version", async () => {
    const t = await createTestApp();
    await t.db.insert(peaks).values({ id: 1, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w" });
    const pack = (await (await t.request("GET", "/v1/peaks/pack/sp86")).json()) as any;
    expect(pack.peaks.map((p: any) => p.name)).toEqual(["Aneto"]);

    expect(((await (await t.request("GET", "/v1/peaks/version")).json()) as any).version).toBeNull();
    await t.db.insert(peakMeta).values({ key: "dataset_version", value: "1784000000000" });
    expect(((await (await t.request("GET", "/v1/peaks/version")).json()) as any).version).toBe(1784000000000);
  });
});

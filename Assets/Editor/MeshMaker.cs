using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

// Generates the few meshes Unity doesn't have as primitives: Tools > Make Meshes.
// Saves them to Assets/Meshes (puffy star, cone, torus).
public static class MeshMaker
{
    const string MeshDir = "Assets/Meshes";

    [MenuItem("Tools/Make Meshes")]
    public static void MakeAll()
    {
        Directory.CreateDirectory(MeshDir);
        Save(MakeStar(5, 0.5f, 0.23f, 0.17f), "Puffy Star");
        Save(MakeCone(0.5f, 1f, 32), "Cone");
        Save(MakeTorus(0.5f, 0.09f, 64, 20), "Torus");
        Save(MakeTorus(0.5f, 0.045f, 64, 16), "Torus Thin");
        AssetDatabase.SaveAssets();
    }

    static void Save(Mesh mesh, string name)
    {
        string path = $"{MeshDir}/{name}.asset";
        var existing = AssetDatabase.LoadAssetAtPath<Mesh>(path);
        if (existing != null)
        {
            // overwrite in place so anything using the mesh keeps its reference
            existing.Clear();
            EditorUtility.CopySerialized(mesh, existing);
            existing.name = name;
            EditorUtility.SetDirty(existing);
            return;
        }
        mesh.name = name;
        AssetDatabase.CreateAsset(mesh, path);
    }

    // Puffy star lying in the XY plane, thickness along Z.
    // The profile is a quarter ellipse from the center out to the rim so it looks inflated.
    public static Mesh MakeStar(int points, float outerR, float innerR, float thickness)
    {
        int perSeg = 6;               // angular samples between a tip and a valley
        int A = points * 2 * perSeg;  // angular samples all the way around
        int K = 6;                    // rings from the center to the rim
        var verts = new List<Vector3>();
        var uvs = new List<Vector2>();
        var tris = new List<int>();

        float RimRadius(float theta)
        {
            float seg = Mathf.PI / points;
            float t = Mathf.Repeat(theta, 2 * seg) / seg;   // 0 at a tip, 1 at a valley, 2 at the next tip
            float k = t <= 1 ? t : 2 - t;
            k = Mathf.SmoothStep(0, 1, k);
            return Mathf.Lerp(outerR, innerR, k);
        }

        for (int side = 0; side < 2; side++)
        {
            float sgn = side == 0 ? 1 : -1;
            int center = verts.Count;
            verts.Add(new Vector3(0, 0, sgn * thickness));
            uvs.Add(new Vector2(0.5f, 0.5f));
            int ringStart = verts.Count;
            for (int k = 1; k <= K; k++)
            {
                float s = (float)k / K;
                float z = sgn * thickness * Mathf.Sqrt(Mathf.Max(0, 1 - s * s));
                for (int i = 0; i < A; i++)
                {
                    float theta = Mathf.PI / 2 + i * 2 * Mathf.PI / A;
                    float r = RimRadius(theta - Mathf.PI / 2) * s;
                    var p = new Vector3(Mathf.Cos(theta) * r, Mathf.Sin(theta) * r, z);
                    verts.Add(p);
                    uvs.Add(new Vector2(p.x + 0.5f, p.y + 0.5f));
                }
            }
            for (int i = 0; i < A; i++)
            {
                int a = ringStart + i, b = ringStart + (i + 1) % A;
                if (side == 1) tris.AddRange(new[] { center, b, a });
                else tris.AddRange(new[] { center, a, b });
            }
            for (int k = 0; k < K - 1; k++)
            {
                int r0 = ringStart + k * A, r1 = ringStart + (k + 1) * A;
                for (int i = 0; i < A; i++)
                {
                    int i1 = (i + 1) % A;
                    if (side == 1)
                    {
                        tris.AddRange(new[] { r0 + i, r0 + i1, r1 + i });
                        tris.AddRange(new[] { r0 + i1, r1 + i1, r1 + i });
                    }
                    else
                    {
                        tris.AddRange(new[] { r0 + i, r1 + i, r0 + i1 });
                        tris.AddRange(new[] { r0 + i1, r1 + i, r1 + i1 });
                    }
                }
            }
        }
        // weld the two rims together so the normals come out smooth around the edge
        int frontRim = 1 + (K - 1) * A;
        int backRim = (1 + K * A) + 1 + (K - 1) * A;
        for (int i = 0; i < tris.Count; i++)
        {
            if (tris[i] >= backRim && tris[i] < backRim + A)
                tris[i] = frontRim + (tris[i] - backRim);
        }
        var mesh = new Mesh();
        mesh.SetVertices(verts);
        mesh.SetUVs(0, uvs);
        mesh.SetTriangles(tris, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        mesh.RecalculateTangents();
        return mesh;
    }

    // Cone pointing down +Z, base at z = -height/2
    public static Mesh MakeCone(float radius, float height, int seg)
    {
        var verts = new List<Vector3>();
        var normals = new List<Vector3>();
        var uvs = new List<Vector2>();
        var tris = new List<int>();
        float slope = radius / height;
        for (int i = 0; i <= seg; i++)
        {
            float a = i * 2 * Mathf.PI / seg;
            var dir = new Vector3(Mathf.Cos(a), Mathf.Sin(a), 0);
            var n = (dir + new Vector3(0, 0, slope)).normalized;
            verts.Add(dir * radius + new Vector3(0, 0, -height / 2));
            normals.Add(n);
            uvs.Add(new Vector2((float)i / seg, 0));
            verts.Add(new Vector3(0, 0, height / 2));
            normals.Add(n);
            uvs.Add(new Vector2((float)i / seg, 1));
        }
        for (int i = 0; i < seg; i++)
        {
            int b0 = i * 2, t0 = i * 2 + 1, b1 = (i + 1) * 2;
            tris.AddRange(new[] { b0, b1, t0 });
        }
        // cap
        int c = verts.Count;
        verts.Add(new Vector3(0, 0, -height / 2));
        normals.Add(Vector3.back);
        uvs.Add(new Vector2(0.5f, 0.5f));
        for (int i = 0; i <= seg; i++)
        {
            float a = i * 2 * Mathf.PI / seg;
            verts.Add(new Vector3(Mathf.Cos(a) * radius, Mathf.Sin(a) * radius, -height / 2));
            normals.Add(Vector3.back);
            uvs.Add(new Vector2(Mathf.Cos(a) * 0.5f + 0.5f, Mathf.Sin(a) * 0.5f + 0.5f));
        }
        for (int i = 0; i < seg; i++) tris.AddRange(new[] { c, c + 1 + i + 1, c + 1 + i });
        var mesh = new Mesh();
        mesh.SetVertices(verts);
        mesh.SetNormals(normals);
        mesh.SetUVs(0, uvs);
        mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        mesh.RecalculateTangents();
        return mesh;
    }

    // Torus around the Y axis. R = ring radius, r = tube radius.
    public static Mesh MakeTorus(float R, float r, int segU, int segV)
    {
        var verts = new List<Vector3>();
        var normals = new List<Vector3>();
        var uvs = new List<Vector2>();
        var tris = new List<int>();
        for (int i = 0; i <= segU; i++)
        {
            float u = i * 2 * Mathf.PI / segU;
            var center = new Vector3(Mathf.Cos(u) * R, 0, Mathf.Sin(u) * R);
            var outward = new Vector3(Mathf.Cos(u), 0, Mathf.Sin(u));
            for (int j = 0; j <= segV; j++)
            {
                float v = j * 2 * Mathf.PI / segV;
                var n = outward * Mathf.Cos(v) + Vector3.up * Mathf.Sin(v);
                verts.Add(center + n * r);
                normals.Add(n);
                uvs.Add(new Vector2((float)i / segU * 4f, (float)j / segV));
            }
        }
        int row = segV + 1;
        for (int i = 0; i < segU; i++)
            for (int j = 0; j < segV; j++)
            {
                int a = i * row + j, b = (i + 1) * row + j;
                tris.AddRange(new[] { a, a + 1, b });
                tris.AddRange(new[] { b, a + 1, b + 1 });
            }
        var mesh = new Mesh();
        mesh.SetVertices(verts);
        mesh.SetNormals(normals);
        mesh.SetUVs(0, uvs);
        mesh.SetTriangles(tris, 0);
        mesh.RecalculateBounds();
        mesh.RecalculateTangents();
        return mesh;
    }
}

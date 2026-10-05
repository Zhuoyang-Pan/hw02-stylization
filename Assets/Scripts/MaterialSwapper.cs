using UnityEngine;

// Cycles through a list of materials when the key is pressed (day -> night -> day ...).
// Pretty much the script from the HW writeup, attached to every part that has a night version.
public class MaterialSwapper : MonoBehaviour
{
    public Material[] materials;
    public KeyCode key = KeyCode.Space;

    private MeshRenderer meshRenderer;
    private int index;

    void Start()
    {
        meshRenderer = GetComponent<MeshRenderer>();
    }

    void Update()
    {
        if (Input.GetKeyDown(key))
        {
            SwapToNextMaterial();
        }
    }

    public void SwapToNextMaterial()
    {
        if (materials == null || materials.Length == 0) return;
        if (meshRenderer == null) meshRenderer = GetComponent<MeshRenderer>();

        index = (index + 1) % materials.Length;
        meshRenderer.sharedMaterial = materials[index];
    }
}

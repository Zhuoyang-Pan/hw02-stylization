using UnityEngine;
using UnityEngine.Rendering.Universal;

// The scene-wide half of "night flight" mode. The MaterialSwappers handle the surface
// materials, this one swaps the lights, the camera background and which full screen
// renderer features are running (pastel post vs night post, day vs night outlines).
public class SceneModeSwitcher : MonoBehaviour
{
    public KeyCode key = KeyCode.Space;

    [Header("Sun")]
    public Light sun;
    public Color daySunColor = Color.white;
    public float daySunIntensity = 1f;
    public Vector3 daySunRotation = new Vector3(50, -30, 0);
    public Color nightSunColor = new Color(0.62f, 0.7f, 1f);
    public float nightSunIntensity = 0.7f;
    public Vector3 nightSunRotation = new Vector3(35, 140, 0);

    [Header("Extra lights")]
    public Light[] dayLights;
    public Light[] nightLights;

    [Header("Objects that only show up during the day (the sea)")]
    public GameObject[] dayOnlyObjects;

    [Header("Camera")]
    public Camera cam;
    public Color dayBackground = Color.white;
    public Color nightBackground = Color.black;

    [Header("Renderer features (on the URP renderer asset)")]
    public ScriptableRendererFeature[] dayFeatures;
    public ScriptableRendererFeature[] nightFeatures;

    public bool IsNight { get; private set; }

    void Start()
    {
        Apply();
    }

    void Update()
    {
        if (Input.GetKeyDown(key))
        {
            Toggle();
        }
    }

    public void Toggle()
    {
        IsNight = !IsNight;
        Apply();
    }

    void Apply()
    {
        if (sun != null)
        {
            sun.color = IsNight ? nightSunColor : daySunColor;
            sun.intensity = IsNight ? nightSunIntensity : daySunIntensity;
            sun.transform.rotation = Quaternion.Euler(IsNight ? nightSunRotation : daySunRotation);
        }
        foreach (var l in dayLights) if (l != null) l.enabled = !IsNight;
        foreach (var l in nightLights) if (l != null) l.enabled = IsNight;
        foreach (var o in dayOnlyObjects) if (o != null) o.SetActive(!IsNight);

        if (cam != null) cam.backgroundColor = IsNight ? nightBackground : dayBackground;

        SetFeatures(IsNight);
    }

    void SetFeatures(bool night)
    {
        foreach (var f in dayFeatures) if (f != null) f.SetActive(!night);
        foreach (var f in nightFeatures) if (f != null) f.SetActive(night);
    }

    // the features live on the renderer asset, so put them back to day mode when we stop playing
    // (otherwise the asset stays in night mode in the editor)
    void OnDisable()
    {
        SetFeatures(false);
    }
}

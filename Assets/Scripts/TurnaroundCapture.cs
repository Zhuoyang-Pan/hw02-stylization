using System.IO;
using UnityEngine;

// Saves numbered frames of the main camera at a fixed frame rate so the turnaround video
// comes out smooth no matter how fast the machine renders. Frames get stitched with ffmpeg:
//   ffmpeg -framerate 30 -i frame_%04d.png -c:v libx264 -pix_fmt yuv420p turnaround.mp4
// Optionally flips day/night once in the middle so the mode switch shows up in the video.
public class TurnaroundCapture : MonoBehaviour
{
    public string outputFolder = "Recordings";
    public int frameRate = 30;
    public int frameCount = 360;
    public int width = 1920;
    public int height = 1080;
    public int switchModeAtFrame = -1;
    public int warmupFrames = 10;   // first few frames can still have shaders compiling
    public bool quitWhenDone = true;

    private Camera cam;
    private RenderTexture rt;
    private Texture2D readback;
    private int frame;
    private int warmup;

    void Start()
    {
        Time.captureFramerate = frameRate;
        Directory.CreateDirectory(outputFolder);

        cam = Camera.main;
        rt = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32);
        readback = new Texture2D(width, height, TextureFormat.RGB24, false);
        cam.targetTexture = rt;
        cam.enabled = false;   // only render when we ask for it
    }

    void LateUpdate()
    {
        if (frame >= frameCount) return;

        if (warmup < warmupFrames)
        {
            cam.Render();
            warmup++;
            return;
        }

        if (frame == switchModeAtFrame)
        {
            foreach (var s in FindObjectsOfType<MaterialSwapper>()) s.SwapToNextMaterial();
            foreach (var s in FindObjectsOfType<SceneModeSwitcher>()) s.Toggle();
        }

        cam.Render();
        var prev = RenderTexture.active;
        RenderTexture.active = rt;
        readback.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        readback.Apply();
        RenderTexture.active = prev;
        File.WriteAllBytes(Path.Combine(outputFolder, $"frame_{frame:D4}.png"), readback.EncodeToPNG());
        frame++;

        if (frame >= frameCount)
        {
            Debug.Log("TurnaroundCapture: wrote " + frameCount + " frames to " + outputFolder);
            cam.targetTexture = null;
            cam.enabled = true;
            if (quitWhenDone)
            {
#if UNITY_EDITOR
                UnityEditor.EditorApplication.isPlaying = false;
#else
                Application.Quit();
#endif
            }
        }
    }
}

using UnityEngine;

// Gentle floating motion: bob up and down and rock a little. Used on the plane and the stars.
public class Bob : MonoBehaviour
{
    public float height = 0.15f;
    public float speed = 1.2f;
    public Vector3 rockDegrees = new Vector3(2f, 0f, 3f);
    public float phase;
    public float spinDegreesPerSecond;

    private Vector3 startPos;
    private Quaternion startRot;

    void Start()
    {
        startPos = transform.localPosition;
        startRot = transform.localRotation;
    }

    void Update()
    {
        float t = Time.time * speed + phase;
        transform.localPosition = startPos + Vector3.up * Mathf.Sin(t) * height;
        Vector3 rock = new Vector3(
            Mathf.Sin(t * 0.8f + 1.3f) * rockDegrees.x,
            Mathf.Sin(t * 0.5f + 0.4f) * rockDegrees.y + Time.time * spinDegreesPerSecond,
            Mathf.Sin(t * 0.9f) * rockDegrees.z);
        transform.localRotation = startRot * Quaternion.Euler(rock);
    }
}

using UnityEngine;

// Flaps the two wing pivots and flies the gull in a circle around its parent.
public class Seagull : MonoBehaviour
{
    public Transform leftWing;
    public Transform rightWing;
    public float flapSpeed = 6f;
    public float flapDegrees = 30f;

    public float orbitRadius = 5f;
    public float orbitSpeed = 20f;   // degrees per second
    public float orbitHeight = 1f;
    public float startAngle;
    public float bobHeight = 0.25f;

    void Update()
    {
        float flap = Mathf.Sin(Time.time * flapSpeed + startAngle) * flapDegrees;
        if (leftWing) leftWing.localRotation = Quaternion.Euler(0, 0, flap);
        if (rightWing) rightWing.localRotation = Quaternion.Euler(0, 0, -flap);

        float a = (startAngle + Time.time * orbitSpeed) * Mathf.Deg2Rad;
        float y = orbitHeight + Mathf.Sin(Time.time * 1.3f + startAngle) * bobHeight;
        transform.localPosition = new Vector3(Mathf.Cos(a) * orbitRadius, y, Mathf.Sin(a) * orbitRadius);

        // face along the circle (tangent direction)
        Vector3 forward = new Vector3(-Mathf.Sin(a), 0, Mathf.Cos(a)) * Mathf.Sign(orbitSpeed);
        transform.localRotation = Quaternion.LookRotation(forward, Vector3.up) * Quaternion.Euler(0, 0, -12f * Mathf.Sign(orbitSpeed));
    }
}

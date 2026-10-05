using UnityEngine;

// Spins around a local axis (propellers).
public class Spin : MonoBehaviour
{
    public Vector3 axis = Vector3.forward;
    public float degreesPerSecond = 720f;

    void Update()
    {
        transform.Rotate(axis, degreesPerSecond * Time.deltaTime, Space.Self);
    }
}

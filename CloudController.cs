using UnityEngine;

public class CloudController : MonoBehaviour
{
    public SDFGenerator sdfGenerator;
    public Material cloudMaterial;

    void Start()
    {
        sdfGenerator.GenerateSDF();
        cloudMaterial.SetTexture("_SDFTex", sdfGenerator.sdfTexture);
    }

    void Update()
    {
        // Ensure the world to local matrix is updated
        Matrix4x4 worldToLocal = transform.worldToLocalMatrix;
        cloudMaterial.SetMatrix("_WorldToLocal", worldToLocal);
    }
}
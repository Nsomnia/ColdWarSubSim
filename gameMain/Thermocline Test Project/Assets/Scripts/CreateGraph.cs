using UnityEngine;
using System.Collections;

/* Should draw a line between two physical objects origins in 3d space.
 * Need to someone how adapt to make it graph data */

public class CreateGraph : MonoBehaviour {

    public Transform origin;
    public Transform destination;
    public float lineDrawSpeed = 6f;

    public float dist;
    public float counter;
    public LineRenderer lineRenderer;


    // Use this for initialization
    void Start()
    {
        lineRenderer = GetComponent<LineRenderer>();
        lineRenderer.SetPosition(0, origin.position);

        lineRenderer.SetWidth(.10f, .10f);

        dist = Vector3.Distance(origin.position, destination.position);

    }

    // Update is called once per frame
    void Update()
    {
        if (counter < dist)
        {

            counter += .1f / lineDrawSpeed;

            float x = Mathf.Lerp(0, dist, counter);

            Vector3 pointA = origin.position;
            Vector3 pointB = destination.position;

            //Get the unit vector in the desired direction, multiply by the desired length and add the starting point.
            Vector3 pointAlongLine = x * Vector3.Normalize(pointB - pointA) + pointA;

            lineRenderer.SetPosition(1, pointAlongLine);

        }
    }
}

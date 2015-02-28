using UnityEngine;
using System.Collections.Generic;

/* Give thanks to the Unity3d community, I'm just one of many to work on this.
 * http://forum.unity3d.com/threads/16540-Wanted-Ocean-shader
 * You are free to use this as you please as long as you do some good deed on the day fist usage.
 * Any changes and improvements you make to this, although not required, would be great
 * if at least shared with me (extra karma points if shared with the community at Unity3d).
 * This version has been optimized for mobile devices.
 * Ported to C# by Joaquin Grech joaquingrech@echoboom.es http://www.echoboomapps.com
 * Optimized a bit more to get extra FPS on mobile by MindBlocks team
 * Added realistic sinking method by MindBlocks team
 * Little tweaks by Odival to work with his iteration of OceanCS.cs
 * */

public class COP_Buoyancy : MonoBehaviour
{

	private OceanCS ocean;
// Water plane at y = 0
	private float mag = 1f;
	private float ypos = 0.0f;
	private List<Vector3> blobs;
	private float ax = 2.0f;
	private float ay = 2.0f;
	private float dampCoeff = .2f;
	public bool sink = false;
	public float sinkForce = 3;
	private List<float> sinkForces;
	
	void Start ()
	{

		rigidbody.centerOfMass = new Vector3 (0.0f, -0.5f, 0.0f);
	
		Vector3 bounds = GetComponent<BoxCollider> ().size;
		float length = bounds.z;
		float width = bounds.x;

		blobs = new List<Vector3> ();

		int i = 0;
		float xstep = 1.0f / (ax - 1f);
		float ystep = 1.0f / (ay - 1f);
	
		sinkForces = new List<float>();
		
		float totalSink = 0;

		for (int x=0; x<ax; x++) {
			for (int y=0; y<ay; y++) {		
				blobs.Add (new Vector3 ((-0.5f + x * xstep) * width, 0.0f, (-0.5f + y * ystep) * length) + Vector3.up * ypos);
				
				float force =  Random.Range(0f,1f);
				
				force = force * force;
				
				totalSink += force;
				
				sinkForces.Add(force);
				i++;
			}		
		}
		
		// normalize the sink forces
		for (int j=0; j< sinkForces.Count; j++)
		{
			sinkForces[j] = sinkForces[j] / totalSink * sinkForce;
		}
		
	}

	void OnEnable ()
	{
		if (ocean == null)
			ocean = GameObject.FindGameObjectWithTag ("Ocean").GetComponent<OceanCS>();
	}

	void Update ()
	{
		int index = 0;
		
		foreach (Vector3 blob in blobs) {
			
			Vector3 wpos = transform.TransformPoint (blob);
			float damp = rigidbody.GetPointVelocity (wpos).y;
			//Vector3 sinkForce = new Vector3(0,0,0);
			
			float buoyancy = mag * (wpos.y);
			if (ocean.enabled && !sink)
			{
				float oHeight = ocean.GetWaterHeightAtLocation (wpos.x, wpos.z);
				if (oHeight > -100) {
					buoyancy = mag * (wpos.y - oHeight);
				}
			}
			if (sink)
			{
				buoyancy = Mathf.Max(buoyancy, -3) + sinkForces[index++] ;
			}
			
			rigidbody.AddForceAtPosition (-Vector3.up * (buoyancy + dampCoeff * damp) , wpos);

		}
	}
	
	//Call this void when you want your boat or any object to sink more naturally
	public void Sink(bool isActive)
	{
	    sink = isActive;	
	}


}

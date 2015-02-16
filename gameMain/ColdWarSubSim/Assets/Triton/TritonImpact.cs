// Copyright (c) 2013 Sundog Software LLC. All rights reserved worldwide.

using UnityEngine;
using System.Collections;
using Triton;

public class TritonImpact : MonoBehaviour {
	
	public double mass = 0.1;
	public double impactorDiameter = 0.1;
	public bool sprayEffects = true;
	public UnityEngine.Vector3 direction = new UnityEngine.Vector3(0, -1, 0);
	public double velocity = 100.0;
	public double sprayScale = 1.0;
	public bool trigger = false;
	
	Triton.Impact impact = null;
	TritonUnity triton = null;
	
	void OnRenderObject () {
		
		if (triton == null) {
			triton = (TritonUnity)(GameObject.FindObjectOfType(typeof(TritonUnity)));
		}
		if (triton != null) {
			Ocean ocean = triton.GetOcean ();
			if (ocean != null) {
				if (trigger) {
					impact = new Triton.Impact(ocean, impactorDiameter, mass, sprayEffects, sprayScale);
					
					UnityEngine.Vector3 pos = gameObject.transform.position;
					if (impact != null) {
						impact.Trigger (new Triton.Vector3(pos.x, pos.y, pos.z),
							new Triton.Vector3(direction.x, direction.y, direction.z),
							velocity, Time.timeSinceLevelLoad);	
						trigger = false;
					}
				}
			}
		}
	}
}




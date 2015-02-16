// Copyright (c) 2013-2014 Sundog Software LLC. All rights reserved worldwide.

using UnityEngine;
using System.Collections;
using Triton;

public class TritonRotorWash : MonoBehaviour {
	
	public double windVelocity = 20;
	public double rotorDiameter = 10;
	public bool sprayEffects = true;
	public bool decalEffects = false;
	public UnityEngine.Vector3 rotorDirection = new UnityEngine.Vector3(0, -1, 0);
	
	Triton.RotorWash rotorWash = null;
	TritonUnity triton = null;
	
	void OnRenderObject () {
		
		if (triton == null) {
			triton = (TritonUnity)(GameObject.FindObjectOfType(typeof(TritonUnity)));
		}
		if (triton != null) {
			Ocean ocean = triton.GetOcean ();
			if (ocean != null) {
				if (rotorWash == null) {
					rotorWash = new Triton.RotorWash(ocean, rotorDiameter, sprayEffects, decalEffects);
				} else {
					UnityEngine.Vector3 pos = gameObject.transform.position;
					
					rotorWash.Update (new Triton.Vector3(pos.x, pos.y, pos.z), 
						new Triton.Vector3(rotorDirection.x, rotorDirection.y, rotorDirection.z), 
						windVelocity, Time.timeSinceLevelLoad);
				}
			}
		}
	}
}



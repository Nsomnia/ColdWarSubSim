// Copyright (c) 2012 Sundog Software LLC. All rights reserved worldwide.

using UnityEngine;
using System.Collections;
using Triton;

public class TritonWakeGenerator : MonoBehaviour {
	
	public double velocity = 0;
	public double bowOffset = 0, length = 100, beamWidth = 20;
	public bool sprayEffects = true;
	public bool propWash = true;
	public double propWashOffset = 0;
	public double draft = 5.0;
	public double sprayVelocityScale = 1.0;
	public double bowWaveScale = 1.0;
	public double bowWaveMax = -1.0;
	public double bowSize = 0.0;
	public double spraySizeScale = 1.0;
	public double lodDistance = 0.0;
	public bool autoUpdate = true;
	public bool testMotion = false;
	public bool clampToSurface = false;
	public int hullSprays = 5;
	
	Triton.WakeGenerator wakeGenerator = null;
	UnityEngine.Vector3 lastPosition;
	int lastFrame = 0;
	float lastTime = 0;
	UnityEngine.Vector3 initialPosition;
	bool testMotionInitialized = false;
	public float testVelocity = 20.0f; //stock 8.0
	TritonUnity triton = null;
	
	void LateUpdate () {
		
		if (testMotion) {
			if (!testMotionInitialized) {
				initialPosition = gameObject.transform.position;
				testMotionInitialized = true;
			}
			float time = Time.timeSinceLevelLoad;
			UnityEngine.Vector3 newPos = initialPosition;
			newPos.z += time * testVelocity;
			gameObject.transform.position = newPos;
			/*
			Camera gameCamera = (Camera)(GameObject.FindObjectOfType (typeof(Camera)));
			UnityEngine.Vector3 camPos = new UnityEngine.Vector3(0, 0, 0);
			if (gameCamera != null) {
				camPos = gameCamera.transform.position;
				camPos.y = 0;
			}
			float time = Time.timeSinceLevelLoad * 0.04f - Mathf.PI * 0.25f;
			UnityEngine.Vector3 newPos = new UnityEngine.Vector3(Mathf.Sin (time) * 100.0f, 0.0f, Mathf.Cos (time) * 100.0f);
			gameObject.transform.position = newPos + camPos;
			*/
		}
		
		UnityEngine.Vector3 dir;
		float angle;
		gameObject.transform.rotation.ToAngleAxis(out angle, out dir);
		UnityEngine.Vector3 curPos = gameObject.transform.position;
		curPos.y = 0;
		
		if (autoUpdate) {
			if (lastTime != 0 && Time.frameCount > lastFrame) {
				UnityEngine.Vector3 delta = curPos - lastPosition;	
				dir = delta;
				dir.Normalize();
				float dist = delta.magnitude;
				float dt = Time.timeSinceLevelLoad - lastTime;
				if (dt > 0) {
					velocity = dist / dt;
				}
			}
			lastPosition = curPos;
			lastFrame = Time.frameCount;
			lastTime = Time.timeSinceLevelLoad;
		}
		
		dir.y = 0;
		dir.Normalize();
		
		if (triton == null) {
			triton = (TritonUnity)(GameObject.FindObjectOfType(typeof(TritonUnity)));
		}
		if (triton != null) {
			Ocean ocean = triton.GetOcean ();
			if (ocean != null) {
				if (wakeGenerator == null) {
					Triton.WakeGeneratorParameters wakeParams = new Triton.WakeGeneratorParameters();
					
					wakeParams.sprayEffects = sprayEffects;
					wakeParams.bowSprayOffset = bowOffset;
					wakeParams.bowWaveOffset = bowOffset;
					wakeParams.length = length;
					wakeParams.beamWidth = beamWidth;
					wakeParams.propWash = propWash;
					wakeParams.propWashOffset = propWashOffset;
					wakeParams.draft = draft;
					wakeParams.sprayVelocityScale = sprayVelocityScale;
					wakeParams.bowWaveScale = bowWaveScale;
					wakeParams.bowWaveMax = bowWaveMax;
					wakeParams.bowSize = bowSize;
					wakeParams.spraySizeScale = spraySizeScale;
					wakeParams.numHullSprays = hullSprays;
					
					wakeGenerator = new Triton.WakeGenerator(ocean, wakeParams);
					wakeGenerator.SetLODDistance(lodDistance);
				} else {
					UnityEngine.Vector3 pos = gameObject.transform.position;
					
					wakeGenerator.Update (new Triton.Vector3(pos.x, pos.y, pos.z), 
						new Triton.Vector3(dir.x, dir.y, dir.z), velocity, Time.timeSinceLevelLoad);
				}
			}
			
			if (clampToSurface) {
				RaycastHit hitInfo = new RaycastHit();
				Ray ray = new Ray((gameObject.transform.position + new UnityEngine.Vector3(0, 500, 0)), new UnityEngine.Vector3(0, -1, 0));
				if (triton.Raycast(ray, out hitInfo, 1000.0f)) {
					gameObject.transform.position = hitInfo.point;
				}
			}
		}
	}
}


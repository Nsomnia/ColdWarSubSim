//#define HAS_SILVERLINING
using UnityEngine;
using System;
using System.Collections;

public class DemoControls : MonoBehaviour {
	
	private float windSpeedSliderValue = 5.0f;
	private float windDirSliderValue = 0.0f;
	private float choppinessSliderValue = 1.6f;
	private float depthSliderValue = 1000.0f;
	private TritonUnity triton = null;
#if HAS_SILVERLINING
	private SilverLining silverLining = null;
	private float todSliderValue = 9.0f;
#endif
	private bool drawGUI = true;
	
	void OnGUI () {
		if (!drawGUI) return;
		
		if (triton != null) {
			// Make a background box
			GUI.Box(new Rect(10,10,150,230), "Triton for Unity");
			GUI.Label(new Rect(25, 35, 100, 20), "Wind Speed");
			windSpeedSliderValue = GUI.HorizontalSlider (new Rect (25, 55, 120, 20), windSpeedSliderValue, 0.0f, 25.0f);
			GUI.Label (new Rect(25, 75, 100, 20), "Wind Direction");
			windDirSliderValue = GUI.HorizontalSlider (new Rect(25, 95, 120, 20), windDirSliderValue, 0.0f, 360.0f);
			GUI.Label (new Rect(25, 115, 100, 20), "Choppiness");
			choppinessSliderValue = GUI.HorizontalSlider(new Rect(25, 135, 120, 20), choppinessSliderValue, 0.0f, 2.0f);
			GUI.Label (new Rect(25, 155, 100, 20), "Depth");
			depthSliderValue = GUI.HorizontalSlider(new Rect(25, 175, 120, 20), depthSliderValue, 1.0f, 1000.0f);
			triton.spray = GUI.Toggle (new Rect(25, 195, 120, 20), triton.spray, "Spray");
			GUI.Label (new Rect(25, 215, 120, 20), "sundog-soft.com");
		

			triton.windSpeed = windSpeedSliderValue;
			triton.windDirection = windDirSliderValue;
			triton.choppiness = choppinessSliderValue;
			triton.depth = depthSliderValue;
		}
#if HAS_SILVERLINING		
		if (silverLining != null) {
			// Make a background box
			GUI.Box(new Rect(170,10,150,170), "SilverLining");
			GUI.Label(new Rect(185, 35, 100, 20), "Time of Day");
			todSliderValue = GUI.HorizontalSlider (new Rect (185, 55, 120, 20), todSliderValue, 0.0f, 24.0f);
			
			bool prevHasCumulus = silverLining.hasCumulusClouds;
			float prevCumulusCoverage = silverLining.cumulusCoverage;
			bool prevHasStratus = silverLining.hasStratusClouds;
			float prevStratusDensity = silverLining.stratusDensity;
			bool prevHasCirrus = silverLining.hasCirrusClouds;
			int prevHour = silverLining.hour;
			int prevMinutes = silverLining.minutes;
			
			silverLining.hasCumulusClouds = GUI.Toggle(new Rect(185, 75, 120, 20), silverLining.hasCumulusClouds, "Cumulus Clouds");
			silverLining.cumulusCoverage = GUI.HorizontalSlider(new Rect(185, 95, 120, 20), silverLining.cumulusCoverage, 0.0f, 1.0f);
			silverLining.hasStratusClouds = GUI.Toggle(new Rect(185, 115, 120, 20), silverLining.hasStratusClouds, "Stratus Clouds");
			silverLining.stratusDensity = GUI.HorizontalSlider(new Rect(185, 135, 120, 20), silverLining.stratusDensity, 0.0f, 1.0f);
			silverLining.hasCirrusClouds = GUI.Toggle(new Rect(185, 155, 120, 20), silverLining.hasCirrusClouds, "Cirrus Clouds");
			
			silverLining.hour = (int)(Math.Floor(todSliderValue));
			silverLining.minutes = (int)((todSliderValue % 1.0) * 60.0);
			
			if (silverLining.hour != prevHour || silverLining.minutes != prevMinutes || silverLining.hasCumulusClouds != prevHasCumulus ||
				silverLining.cumulusCoverage != prevCumulusCoverage || silverLining.hasStratusClouds != prevHasStratus ||
				silverLining.stratusDensity != prevStratusDensity || silverLining.hasCirrusClouds != prevHasCirrus) {
				triton.ForceEnvUpdate();
			}
		}
#endif
	}
	// Use this for initialization
	void Start () {
		triton = (TritonUnity)(GameObject.FindObjectOfType(typeof(TritonUnity)));
#if HAS_SILVERLINING
		silverLining = (SilverLining)(GameObject.FindObjectOfType(typeof(SilverLining)));
#endif
	}
	
	// Update is called once per frame
	void Update () {
		if (Input.GetKey(KeyCode.Escape))
	    {
	        Application.Quit();
	    }
		
		if (Input.GetKeyDown (KeyCode.C))
		{
			drawGUI = !drawGUI;
		}
		
#if HAS_SILVERLINING
		if (silverLining != null && triton != null)
		{
			triton.aboveWaterFogColor = silverLining.GetSkyLightColor();	
		}
#endif
	}
}
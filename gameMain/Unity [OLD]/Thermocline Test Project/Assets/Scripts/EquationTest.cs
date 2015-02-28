using UnityEngine;
using System.Collections;

//This script prints to the console the speed of sound in feet per second taking in two arguments temperate in f and depth in feet. 
//ie. SpeedSound(32.0f,521.5f); will tell you the speed of sound in ft/s in the ocean at 521 feet 6 inches deep with a water temp
//of 32 f

public class EquationTest : MonoBehaviour 
{
    public float soundSpeed;

	// Use this for initialization
	void Start () 
    {
        SpeedSound(32.0f, 1.0f);
        Debug.Log(soundSpeed);
	}


	// Update is called once per frame
	void Update () 
    {
	}

    void SpeedSound(float temp, float depth)
    {
        //Speed of sound in feet per second = this equation. temp is in F. Depth is in feet. Assumes average salinity. 
        soundSpeed = (4388 + (11.25f * temp) + (0.0182f * depth));
    }
}
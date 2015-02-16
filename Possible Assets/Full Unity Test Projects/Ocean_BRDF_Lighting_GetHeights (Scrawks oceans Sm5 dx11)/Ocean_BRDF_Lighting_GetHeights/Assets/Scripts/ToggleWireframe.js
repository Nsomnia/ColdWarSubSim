#pragma strict

var wireframeCamera : GameObject;
var isOn : boolean  = false;

function Start()
{
	wireframeCamera.GetComponent(Camera).camera.enabled = isOn;
}

function Update () 
{
	var b : boolean = wireframeCamera.GetComponent(Camera).camera.enabled;
	
	if(Input.GetKeyDown(KeyCode.F2)) wireframeCamera.GetComponent(Camera).camera.enabled = !b;
}
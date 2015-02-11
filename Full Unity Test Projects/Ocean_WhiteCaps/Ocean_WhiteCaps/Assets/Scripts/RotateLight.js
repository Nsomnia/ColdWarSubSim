#pragma strict

var speed : float = 50.0;

function Update () 
{

	if(Input.GetKey(KeyCode.KeypadMinus))
	{
		transform.Rotate(Vector3(-Time.deltaTime*speed, 0, 0));
	}
	
	if(Input.GetKey(KeyCode.KeypadPlus))
	{
		transform.Rotate(Vector3(Time.deltaTime*speed, 0, 0));
	}
	
}


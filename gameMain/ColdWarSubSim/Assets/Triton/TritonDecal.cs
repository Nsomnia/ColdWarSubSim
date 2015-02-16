// Copyright (c) 2013-2014 Sundog Software LLC. All rights reserved worldwide.

using UnityEngine;
using System.Collections;
using Triton;

public class TritonDecal : MonoBehaviour
{
	public Texture2D texture;
	public float size = 10.0f;
	public float opacity = 1.0f;
	
	private Texture2D currentTexture;
	private float currentSize, currentOpacity = 1.0f;
	private float currentScaleX = 1.0f, currentScaleZ = 1.0f;
	private UnityEngine.Vector3 currentPos;
	private System.IntPtr currentDecal;
	
	// Use this for initialization
	void Start ()
	{
	}
	
	void OnDestroy()
	{
		UnityBindings.DeleteDecal(currentDecal);
		currentDecal = (System.IntPtr)0;
		currentTexture = null;
		currentSize = 0;
		currentPos = new UnityEngine.Vector3(0,0,0);
	}
	
	void OnDisable()
	{
		UnityBindings.DeleteDecal(currentDecal);
		currentDecal = (System.IntPtr)0;
		currentTexture = null;
		currentSize = 0;
		currentPos = new UnityEngine.Vector3(0,0,0);
	}
	
	// Update is called once per frame
	void Update ()
	{
		if (enabled) {
			UnityEngine.Vector3 pos = gameObject.transform.position;
			if (size != currentSize || pos != currentPos || texture != currentTexture) {
				UnityBindings.DeleteDecal (currentDecal);
				currentDecal = UnityBindings.AddDecal (texture.GetNativeTexturePtr(), size, pos.x, pos.y, pos.z);
				if (currentDecal != (System.IntPtr)0) {
					currentPos = pos;
					currentSize = size;
					currentTexture = texture;
				}
			}
			
			UnityEngine.Vector3 scale = gameObject.transform.localScale;
			if (scale.x != currentScaleX || scale.z != currentScaleZ) {
				if (currentDecal != (System.IntPtr)0) {
					UnityBindings.SetDecalScale(currentDecal, scale.x, scale.z);
					currentScaleX = scale.x;
					currentScaleZ = scale.z;
				}
			}
			
			if (opacity != currentOpacity) {
				if (currentDecal != (System.IntPtr)0) {
					UnityBindings.SetDecalOpacity(currentDecal, opacity);
					currentOpacity = opacity;
				}
			}
		}
	}
	
	void OnDrawGizmos( )
	{
		Color color = Color.cyan;
		color.a = opacity;
		
		UnityEngine.Vector3 scale = new UnityEngine.Vector3( currentScaleX, 0.0f, currentScaleZ ) * size;
		scale.y = 0.01f;
		
		Gizmos.color = color;
		Gizmos.DrawCube( gameObject.transform.position, scale );
	}
}


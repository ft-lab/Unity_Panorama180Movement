//----------------------------------------------------------------.
// GaussianによるBlur処理.
//----------------------------------------------------------------.
Shader "Hidden/Panorama180View/Blur"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
        _BlurIntensity ("BlurIntensity", Range (0, 10.0)) = 1.0
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" "Queue"="geometry" }

		LOD 100
        //ZWrite On

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			// depthテクスチャ.
			sampler2D _MainTex;

            float _BlurIntensity;		// ブラーの強さ.
			float _TextureWidth;		// テクスチャの幅.
			float _TextureHeight;		// テクスチャの高さ.

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			float4 frag (v2f i) : SV_Target
			{
				float xD = 1.0 / (float)_TextureWidth;
				float yD = 1.0 / (float)_TextureHeight;

                float2 uv = i.uv;
                float4 col = tex2D(_MainTex, i.uv);
				float4 col2;

				int cou = 1;
				float2 uvP = float2(xD, yD);
				for (int i = 0; i < 3; ++i) {
/*					
					col += tex2D(_MainTex, float2(min(1.0, uv.x + uvP.x), uv.y));
					col += tex2D(_MainTex, float2(max(0.0, uv.x - uvP.x), uv.y));
					col += tex2D(_MainTex, float2(uv.x, min(1.0, uv.y + uvP.y)));
					col += tex2D(_MainTex, float2(uv.x, max(0.0, uv.y - uvP.y)));
			*/
					{
						col2 = tex2D(_MainTex, float2(min(1.0, uv.x + uvP.x), uv.y));
						col.x = min(col.x, col2.x);
						col.y = min(col.y, col2.y);
						col.z = min(col.z, col2.z);
					}
					{
						col2 = tex2D(_MainTex, float2(max(0.0, uv.x - uvP.x), uv.y));
						col.x = min(col.x, col2.x);
						col.y = min(col.y, col2.y);
						col.z = min(col.z, col2.z);
					}
					{
						col2 = tex2D(_MainTex, float2(uv.x, min(1.0, uv.y + uvP.y)));
						col.x = min(col.x, col2.x);
						col.y = min(col.y, col2.y);
						col.z = min(col.z, col2.z);
					}
					{
						col2 = tex2D(_MainTex, float2(uv.x, max(0.0, uv.y - uvP.y)));
						col.x = min(col.x, col2.x);
						col.y = min(col.y, col2.y);
						col.z = min(col.z, col2.z);
					}

					uvP.x += xD;
					uvP.y += yD;
					cou += 4;
				}
				//col /= (float)cou;

                return col;
            }
            ENDCG
        }
    }
}

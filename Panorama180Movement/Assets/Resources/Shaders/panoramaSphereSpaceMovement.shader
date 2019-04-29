//----------------------------------------------------------------.
// 球に対して、Equirectangular180 SBSのステレオパノラマ投影を行う.
// このときに、周囲を補間して移動できるようにする.
//----------------------------------------------------------------.
Shader "Hidden/Panorama180View/panoramaSphereSpaceMovement"
{
	Properties
	{
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" "Queue"="geometry-100" }

		LOD 100
        ZWrite On

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

            #define UNITY_PI2 (UNITY_PI * 2.0)
			#define MIN_VAL (1e-5)
			#define F_ONE_MIN 0.99999

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

			// サンプリング用のPanorama180テクスチャ.
			sampler2D _Tex1;
			sampler2D _Tex2;
			sampler2D _TexDepth1;
			sampler2D _TexDepth2;

            float _Intensity;

			float4 _BasePos;		// カメラのはじめの中心位置.
			float4 _PrevPos;		// 1つ前のカメラ位置.
			float4 _CurrentPos;		// 現在のカメラ位置.
			float4 _Pos1, _Pos2;	// サンプリングのカメラ位置.

			float _BlendV = 0.0;	// 2画像のブレンド値.

			int _DepthTextureWidth = 2048;		// depthテクスチャの幅.
			int _DepthTextureHeight = 1024;		// depthテクスチャの高さ.
			int _SpatialInterpolation = 1;		// 空間補間を行うかどうか.

			float _CameraNearPlane = 0.1;		// カメラの近クリップ面.
			float _CameraFarPlane  = 100.0;		// カメラの遠クリップ面.

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			/**
			 * 視線方向のベクトルを計算.
			 */
			float3 calcVDir (float2 _uv) {
				float theta = UNITY_PI2 * (_uv.x - 0.5);
				float phi   = UNITY_PI * (_uv.y - 0.5);
				float sinP = sin(phi);
				float cosP = cos(phi);
				float sinT = sin(theta);
				float cosT = cos(theta);
				float3 vDir = float3(cosP * sinT, sinP, cosP * cosT);
				return vDir;
			}

			/**
			 * ワールド座標よりUVを計算.
			 */
			float2 calcWPosToUV (float3 wPos, float3 centerPos) {
				float3 vDir = normalize(wPos - centerPos);
				float sinP = vDir.y;
				float phi = asin(sinP);		// -90 ～ + 90の範囲.
				float cosP = cos(phi);
				if (abs(cosP) < 1e-5) cosP = 1e-5;
				float sinT = vDir.x / cosP;
				float cosT = vDir.z / cosP;
				sinT = max(sinT, -1.0);
				sinT = min(sinT,  1.0);
				cosT = max(cosT, -1.0);
				cosT = min(cosT,  1.0);
				float a_s = asin(sinT);
				float a_c = acos(cosT);
				float theta = (a_s >= 0.0) ? a_c : (UNITY_PI2 - a_c);

				float2 uv = float2((theta / UNITY_PI2) + 0.5, (phi / UNITY_PI) + 0.5);
				if (uv.x < 0.0) uv.x += 1.0;
				if (uv.x > 1.0) uv.x -= 1.0;
				return uv;
			}

			/**
			 * テクスチャ上のUV位置を計算 (Equirectangular180 SideBySide).
			 */
			float2 calcUV (float2 _uv) {
                float2 uv = _uv;
				uv.x -= 0.25;
				if (unity_StereoEyeIndex == 1) {
					uv.x += 0.5;
				}
				return uv;
			}

			/**
			 * SBSでのUVから、単体パノラマとしてのUVに変換.
			 */
			float2 calcUVInv (float2 _uv) {
                float2 uv = _uv;
				if (unity_StereoEyeIndex == 1) {
					uv.x -= 0.5;
				}
				uv.x += 0.25;
				return uv;
			}

			/**
			 * 指定のワールド座標位置より、Panorama180でのUVを計算.
			 * @param[in] centerPos  中心位置.
			 * @param[in] wPos       ワールド座標位置.
			 * @return 180度パノラマ（ステレオ）でのUV値 (x < 0.5は左目、x >= 0.5は右目).
			 */
			float2 calcWorldPosToUV (float3 centerPos, float3 wPos) {
				float2 retUV = calcWPosToUV(wPos, centerPos);
				retUV = calcUV(retUV);
				return retUV;
			}

			/**
			 * UV位置と方向ベクトルより、衝突するワールド座標位置を計算.
			 * @param[in] depthTex  depthテクスチャ.
			 * @param[in] uv        UV値 (x < 0.5の場合は左目、x >= 0.5の場合は右目).
			 * @param[in] cPos      カメラのワールド座標での中心.
			 * @param[in] vDir      視線ベクトル.
			 */
			float3 calcUVToWorldPos (sampler2D depthTex, float2 uv, float3 cPos, float3 vDir) {
				float depth = tex2D(depthTex, uv).r;

				// depth値から、カメラからの距離に変換.
				depth = (depth >= 0.99999) ? _CameraFarPlane : (_CameraNearPlane / (1.0 - depth));
				depth = min(depth, _CameraFarPlane);

				return (vDir * depth) + cPos;
			}

			/**
			 * _Pos1, _Pos2からvDir方向に伸ばしたZ距離zDist1,zDist2を指定し、_BlendVの位置での色を計算.
			 * @param[in] zDist1  _Pos1からvDir方向に伸ばした交点までの距離.
			 * @param[in] zDist2  _Pos2からvDir方向に伸ばした交点までの距離.
			 * @param[in] wPosC0  _Pos1 - _Pos2の間の_BlendVの割合の位置.
			 * @param[in] vDir    調査する視線ベクトル.
			 * @param[in] forceStore  処理に失敗している場合でも、強制的に色を格納する場合はtrue.			 
			 * @return 交点での色。x < 0.0の場合は処理に失敗.
			 */
			float4 estimateColor (float zDist1, float zDist2, float3 wPosC0, float3 vDir, bool forceStore = false)  {
				// depthをワールド座標位置に変換.
				float3 wPos1_b = (vDir * zDist1) + _Pos1.xyz;
				float3 wPos2_b = (vDir * zDist2) + _Pos2.xyz;

				float3 wPosC = lerp(wPos1_b, wPos2_b, _BlendV);

				// _Pos1が中心のパノラマはwPos1。これがwPosCに移動するときのUVを計算.
				float2 newUV1 = calcWorldPosToUV(_Pos1, wPosC);
				float2 newUV2 = calcWorldPosToUV(_Pos2, wPosC);

				// UV値より、それぞれのワールド座標位置を計算.
				float3 wPosA = calcUVToWorldPos(_TexDepth1, newUV1, _Pos1, normalize(wPosC - _Pos1));
				float3 wPosB = calcUVToWorldPos(_TexDepth2, newUV2, _Pos2, normalize(wPosC - _Pos2));

				float angle1 = dot(normalize(wPosA - wPosC0), vDir);
				float angle2 = dot(normalize(wPosB - wPosC0), vDir);
				float4 col1 = tex2D(_Tex1, newUV1);
				float4 col2 = tex2D(_Tex2, newUV2);

				float4 col = float4(-1, 0, 0, 1);
				if (angle1 > F_ONE_MIN && angle2 > F_ONE_MIN) {
					col = lerp(col1, col2, _BlendV);
				} else if (angle1 > F_ONE_MIN) {
					col = col1;
				} else if (angle2 > F_ONE_MIN) {
					col = col2;
				} else if (forceStore) {
					col = lerp(col1, col2, _BlendV);
				}
				return col;
			}

			float4 frag (v2f i) : SV_Target
			{
                float2 uv = i.uv;

				if (uv.x < 0.25 || uv.x > 0.75) return float4(0.0, 0.0, 0.0, 1.0);

				// UV値を計算.
				uv = calcUV(uv);

				// 空間補間を行わない場合.
				if (_SpatialInterpolation == 0) {
					float4 col1 = tex2D(_Tex1, uv);
					float4 col2 = tex2D(_Tex2, uv);
					float4 col = lerp(col1, col2, _BlendV);
	                col.rgb *= _Intensity;
					return col;
				}

				// 視線ベクトル.
				float2 uv2 = float2(i.uv.x, i.uv.y);
				float3 vDir = calcVDir(uv2);

				//---------------------------------------------------------------.
				// 線形にdepth1-depth2に変化する場合は、この間で線形補間するだけ.
				//---------------------------------------------------------------.
				// ワールド座標上で、wPosC0からvDir方向に伸ばした直線上に最終的な交差位置が存在する.
				float3 wPosC0 = lerp(_Pos1, _Pos2, _BlendV);

				float depth1 = tex2D(_TexDepth1, uv).r;
				float depth2 = tex2D(_TexDepth2, uv).r;

				// depthをビュー座標上の距離に変換.
				depth1 = (depth1 >= F_ONE_MIN) ? _CameraFarPlane : (_CameraNearPlane / (1.0 - depth1));
				depth2 = (depth2 >= F_ONE_MIN) ? _CameraFarPlane : (_CameraNearPlane / (1.0 - depth2));
				depth1 = min(depth1, _CameraFarPlane);
				depth2 = min(depth2, _CameraFarPlane);

				float depth1_b = depth1;
				float depth2_b = depth2;
				float minDepth = min(depth1_b, depth2_b);
				float maxDepth = max(depth1_b, depth2_b);

				float4 col = estimateColor(depth1_b, depth2_b, wPosC0, vDir);
				if (col.x < 0.0) {
					col = estimateColor(minDepth, minDepth, wPosC0, vDir);
					if (col.x < 0.0) {
						col = estimateColor(maxDepth, maxDepth, wPosC0, vDir);
						if (col.x < 0.0) {
							col = estimateColor(depth1_b, depth2_b, wPosC0, vDir, true);
						}
					}
				}

                col.rgb *= _Intensity;

				return col;
			}
			ENDCG
		}
	}
}


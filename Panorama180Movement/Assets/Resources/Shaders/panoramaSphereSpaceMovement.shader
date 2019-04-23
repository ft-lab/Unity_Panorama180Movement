//----------------------------------------------------------------.
// 球に対して、Equirectangular180 SBSのステレオパノラマ投影を行う.
// このときに、周囲を補間して移動できるようにする.
//----------------------------------------------------------------.
Shader "Hidden/Panorama180View/panoramaSphereSpaceMovement"
{
	Properties
	{
		//_MainTex ("Texture", 2D) = "white" {}
        //_Intensity ("Intensity", Range (0, 10.0)) = 1.0
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

			//sampler2D _MainTex;
			//float4 _MainTex_ST;
            float _Intensity;

			float4 _BasePos;		// カメラのはじめの中心位置.
			float4 _PrevPos;		// 1つ前のカメラ位置.
			float4 _CurrentPos;		// 現在のカメラ位置.
			float4 _Pos1, _Pos2;	// サンプリングのカメラ位置.

			float _BlendV = 0.0;	// 2画像のブレンド値.

			int _DepthTextureWidth = 2048;		// depthテクスチャの幅.
			int _DepthTextureHeight = 1024;		// depthテクスチャの高さ.

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
			 * DepthのUVをピクセルの中心になるようにする.
			 */
			float2 recalcUV (float2 uv) {
				float px = 1.0 / (float)_DepthTextureWidth;
				float py = 1.0 / (float)_DepthTextureHeight;

				int ix = min((int)floor(uv.x * _DepthTextureWidth), _DepthTextureWidth - 1);
				int iy = min((int)floor(uv.y * _DepthTextureHeight), _DepthTextureHeight - 1);
				uv.x = (float)ix * px;	// + (px * 0.5);
				uv.y = (float)iy * py;	// + (py * 0.5);
				return uv;
			}

			/**
			 * 指定のテクスチャの周辺のdepthを取得.
			 * @param[in] depthTex  Depthテクスチャ.
			 * @param[in] uv        UV.
			 * @param[in] rangeV    探索エリア.
			 */
			float getDepth (sampler2D depthTex, float2 uv, float rangeV = 0.001) {
				float depthV = tex2D(depthTex, uv).r;

				if (rangeV > 0.0) {
					float rangeVY = rangeV * 2.0;
					for (int i = 0; i < 3; ++i) {
						float2 uv1 = float2(max(uv.x - rangeV, 0.0), uv.y);
						float2 uv2 = float2(min(uv.x + rangeV, 1.0), uv.y);
						float2 uv3 = float2(uv.x, max(uv.y - rangeVY, 0.0));
						float2 uv4 = float2(uv.x, min(uv.y + rangeVY, 1.0));

						depthV = min(depthV, tex2D(depthTex, uv1).r);
						depthV = min(depthV, tex2D(depthTex, uv2).r);
						depthV = min(depthV, tex2D(depthTex, uv3).r);
						depthV = min(depthV, tex2D(depthTex, uv4).r);

						rangeV *= 2.0;
						rangeVY *= 2.0;
					}
				}

				return depthV;
			}

			/**
			 * UV位置と方向ベクトルより、衝突するワールド座標位置を計算.
			 * @param[in] depthTex  depthテクスチャ.
			 * @param[in] uv        UV値 (x < 0.5の場合は左目、x >= 0.5の場合は右目).
			 * @param[in] cPos      カメラのワールド座標での中心.
			 * @param[in] vDir      視線ベクトル.
			 */
			float3 calcUVToWorldPos (sampler2D depthTex, float2 uv, float3 cPos, float3 vDir, float rangeV = 0.0) {
				float depth = getDepth(depthTex, uv, rangeV);
				//tex2D(depthTex, uv).r;

				// depth値から、カメラからの距離に変換.
				depth = (depth >= 0.99999) ? _CameraFarPlane : (_CameraNearPlane / (1.0 - depth));
				depth = min(depth, _CameraFarPlane);

				return (vDir * depth) + cPos;
			}

			/**
			 * cPosが中心のカメラより、指定のワールド位置(targetStartPos)からvDir方向に延ばした直線上に.
			 * depthを考慮した交点があるか計算.
			 * @param[in] colorTex  RGBテクスチャ.
			 * @param[in] depthTex  depthテクスチャ.
			 * @param[in] cPos      カメラのワールド座標での中心.
			 * @param[in] vDir      視線ベクトル.
			 * @param[in] targetStartPos  走査を開始する始点位置。ここからvDir方向に走査することになる.
			 * @return 交点での色。x < 0.0の場合は処理に失敗.
			 */
			float4 estimateColor (sampler2D colorTex, sampler2D depthTex, float3 cPos, float3 vDir, float3 targetStartPos) {
				float minLenP = 0.0;
				float maxLenP = _CameraFarPlane;

				float minLen = minLenP;
				float maxLen = maxLenP;
				float lenA[8 + 1];
				float minLenA[8 + 1];
				float2 minUVA[8 + 1];
				float3 wPos, wPosD, wPos2, vDir2;
				int minPosI;
				float minLenV = -1.0;
				float2 minUV = float2(0, 0);
				
				float mLen;

				float dDist = 1.0 / (float)_DepthTextureWidth;

				// 基準となるUV値を取得.
				//float2 uv0 = calcWorldPosToUV(cPos, cPos + vDir);
				float2 uv0 = calcWPosToUV(cPos + vDir, cPos);
				uv0 = calcUV(uv0);

				for (int i = 0; i < 10; ++i) {
					// targetStartPosからvDirに伸ばした直線上のサンプル点の距離位置.
					float dLen = (maxLen - minLen) / (float)(8 - 1);
					float lenPos = minLen;
					wPos = targetStartPos + (vDir * minLen);
					wPosD = vDir * dLen;
					for (int j = 0; j < 8; ++j) {
						// 指定のワールド位置wPosで、cPosからの交差があるか.
						float2 uv = calcWorldPosToUV(cPos, wPos);	// wPosをUV位置に変換.
						//float2 uv = calcWPosToUV(wPos, cPos);
						//uv = calcUV(uv);

						vDir2 = normalize(wPos - cPos);
						wPos2 = calcUVToWorldPos(depthTex, uv, cPos, vDir2);	// depthを考慮した交点のワールド位置.
						minLenA[j] = length(wPos2 - wPos);
						minUVA[j]  = uv;
						lenA[j]    = lenPos;

						lenPos += dLen;
						wPos += wPosD;
					}

					// minLenA[]の一番小さい値を採用.
					minPosI = -1;
					mLen    = -1.0;
					for (int j2 = 0; j2 < 8; ++j2) {
						if (minLenA[j2] < _CameraFarPlane && (minPosI < 0 || minLenA[j2] < mLen)) {
							minPosI = j2;
							mLen    = minLenA[j2];
						}
					}
					if (minPosI < 0) break;

					minLenV = minLenA[minPosI];
					minUV   = minUVA[minPosI];

					// 収束.
					float lenD = (maxLen - minLen) * 0.128;
					if (lenD < 0.001) break;

					float curLen = lenA[minPosI];
					minLen = max(minLenP, curLen - lenD);
					maxLen = min(maxLenP, curLen + lenD);
				}

				float chkMaxLen = 0.01;
//				if (minLenV > chkMaxLen) return float4(-1, -1, -1, 1);
				if (minLenV < 0.0) return float4(0, 0, 1, 1);
				if (minLenV > chkMaxLen) return float4(1, 0, 0, 1);

				return tex2D(colorTex, minUV);
/*
				float dV = tex2D(depthTex, minUV).r;
				dV = (dV >= 0.99999) ? _CameraFarPlane : (_CameraNearPlane / (1.0 - dV));
				dV = min(dV, _CameraFarPlane);
				dV = (dV - _CameraNearPlane) / (_CameraFarPlane - _CameraNearPlane);

				return float4(dV, dV, dV, minLenV);
				*/
			}

			float4 frag (v2f i) : SV_Target
			{
                float2 uv = i.uv;

				if (uv.x < 0.25 || uv.x > 0.75) return float4(0.0, 0.0, 0.0, 1.0);

				// UV値を計算.
				uv = calcUV(uv);

				// 視線ベクトル.
				float2 uv2 = float2(i.uv.x, i.uv.y);
				float3 vDir = calcVDir(uv2);

				//---------------------------------------------------------------.
/*				
				// 中間位置。ここからvDirの方向で衝突がある位置を採用することになる.
				float3 PosC0 = lerp(_Pos1, _Pos2, _BlendV);

				float4 col1 = estimateColor(_Tex1, _TexDepth1, _Pos1, vDir, PosC0);
				float4 col2 = estimateColor(_Tex2, _TexDepth2, _Pos2, vDir, PosC0);
				float4 col = float4(0, 0, 0, 1);

				if (col1.x >= 0.0 && col2.x >= 0.0) {
					if (col1.w < col2.w) {
						col = col1;
					} else {
						col = col2;
					}
//					col = (col1 + col2) * 0.5;
				} else if (col1.x >= 0.0) {
					col = col1;
				} else if (col2.x >= 0.0) {
					col = col2;
				}

				col.a = 1.0;
                col.rgb *= _Intensity;
*/
				//---------------------------------------------------------------.
/*
				// depthを取得.
				float dDist = 1.0 / (float)_DepthTextureWidth;
				float depth1 = getDepth(_TexDepth1, uv, dDist);
				float depth2 = getDepth(_TexDepth2, uv, dDist);
				float nearPlane = _CameraNearPlane;
				float farPlane  = _CameraFarPlane;

				// depthをワールド座標上の距離に変換.
				//depth1 = depth1 * (farPlane - nearPlane) + nearPlane;
				//depth2 = depth2 * (farPlane - nearPlane) + nearPlane;
				depth1 = (depth1 >= 0.99999) ? farPlane : (nearPlane / (1.0 - depth1));
				depth2 = (depth2 >= 0.99999) ? farPlane : (nearPlane / (1.0 - depth2));
				depth1 = min(depth1, farPlane);
				depth2 = min(depth2, farPlane);

				// ワールド座標位置に変換.
				float3 wPos1 = (vDir * depth1) + _Pos1.xyz;
				float3 wPos2 = (vDir * depth2) + _Pos2.xyz;

				// 中間位置。ここからvDirの方向で衝突がある位置を採用することになる.
				float3 PosC0 = lerp(_Pos1, _Pos2, _BlendV);

				//---------------------------------------------------------------.
				// wPos1-wPos2から、_Pos1でのパノラマでのUVが計算できる.
				// UVの移動量よりその間のdepthの移行は把握できる.
				// このときのUVは、ステレオパノラマを考慮したUV.
				float2 newUV1 = calcWorldPosToUV(_Pos1, wPos1);
				float2 newUV2 = calcWorldPosToUV(_Pos1, wPos2);
				float2 newUV = lerp(newUV1, newUV2, _BlendV);		// 実際は曲面上.

				// 単体パノラマとしてのUVに変換.
				float2 newUV0 = calcUVInv(newUV);

				float3 vDir2 = calcVDir(newUV0);

				// depthより、カメラから距離に変換.
				float nDepth = getDepth(_TexDepth1, newUV, 0.0);
				nDepth = (nDepth >= 0.99999) ? farPlane : (nearPlane / (1.0 - nDepth));

				// TODO : depthより、wPosPからvDir方向の衝突位置を計算.
				float3 wPosC = vDir2 * nDepth + _Pos1.xyz;

				newUV1 = calcWorldPosToUV(_Pos1, wPosC);
				newUV2 = calcWorldPosToUV(_Pos2, wPosC);

				float4 col1 = tex2D(_Tex1, newUV1);
				float4 col2 = tex2D(_Tex2, newUV2);
				float4 col = lerp(col1, col2, _BlendV);

                col.rgb *= _Intensity;
*/
				//---------------------------------------------------------------.
				// 線形にdepth1-depth2に変化する場合は、この間で線形補間するだけ.
				//---------------------------------------------------------------.
				float depth1 = tex2D(_TexDepth1, uv).r;		//getDepth(_TexDepth1, uv, 0.0);
				float depth2 = tex2D(_TexDepth2, uv).r;		//getDepth(_TexDepth2, uv, 0.0);
				float nearPlane = _CameraNearPlane;
				float farPlane  = _CameraFarPlane;

				// depthをワールド座標上の距離に変換.
				depth1 = (depth1 >= 0.99999) ? farPlane : (nearPlane / (1.0 - depth1));
				depth2 = (depth2 >= 0.99999) ? farPlane : (nearPlane / (1.0 - depth2));
				depth1 = min(depth1, farPlane);
				depth2 = min(depth2, farPlane);

				float depth1_b = depth1;
				float depth2_b = depth2;

				// depthが近いほうに近づける。これにより、手前で視差が大きい移動がスムーズになる.
				if (depth1 < farPlane - MIN_VAL && depth2 < farPlane - MIN_VAL) {
					float minDepth = min(depth1, depth2);
					float fV = 0.5;
					depth1_b = lerp(depth1, minDepth, fV);
					depth2_b = lerp(depth2, minDepth, fV);
				}

				// depthをワールド座標位置に変換.
				float3 wPos1_b = (vDir * depth1_b) + _Pos1.xyz;
				float3 wPos2_b = (vDir * depth2_b) + _Pos2.xyz;

				float3 wPosC = lerp(wPos1_b, wPos2_b, _BlendV);

				// _Pos1が中心のパノラマはwPos1。これがwPosCに移動するときのUVを計算.
				float2 newUV1 = calcWorldPosToUV(_Pos1, wPosC);
				float2 newUV2 = calcWorldPosToUV(_Pos2, wPosC);

				float4 col1 = tex2D(_Tex1, newUV1);
				float4 col2 = tex2D(_Tex2, newUV2);
//				float4 col1 = tex2D(_TexDepth1, newUV1);
//				float4 col2 = tex2D(_TexDepth2, newUV2);

				float4 col = lerp(col1, col2, _BlendV);
/*
				float dV = col.r;
				dV = (dV >= 0.99999) ? _CameraFarPlane : (_CameraNearPlane / (1.0 - dV));
				dV = min(dV, _CameraFarPlane);
				dV = (dV - _CameraNearPlane) / (_CameraFarPlane - _CameraNearPlane);
				col = float4(dV, dV, dV, 1);
*/
                col.rgb *= _Intensity;

				return col;
			}
			ENDCG
		}
	}
}


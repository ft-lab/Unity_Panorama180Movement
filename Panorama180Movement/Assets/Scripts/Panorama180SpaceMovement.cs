/**
 * カメラの平行移動で、間を補間.
 */
using System.Collections;
using System.Collections.Generic;
using UnityEngine.XR;
using UnityEngine;
using UnityEngine.Rendering;

namespace Panorama180View {
    [RequireComponent(typeof(Camera))]
    public class Panorama180SpaceMovement : MonoBehaviour {
        [SerializeField, Range(0.0f, 10.0f)] float intensity = 1.0f;           // 明るさ.
        [SerializeField] Vector3 startPos = new Vector3(0, 0, 0);           // Camera start position.
        [SerializeField] Vector3 endPos = new Vector3(1, 0, 0);             // Camera end position.
        [SerializeField] float rotationY = 0.0f;                            // Y軸中心の回転.
        [SerializeField] bool spatialInterpolation = true;                  // 空間補間.

        private GameObject m_backgroundSphere = null;       // 背景球.
        private Material m_backgroundSphereMat = null;      // 背景のマテリアル.

        private Material m_blurMat = null;                  // depthにブラーをかけるマテリアル.

        private float radius = 500.0f;

        private Vector3 basePos = new Vector3(0.0f, 1.6f, 0.0f);
        private Vector3 prevPos;

        private Texture2D [] m_Texture2DList = null;             // RGBテクスチャ.
        private RenderTexture [] m_Texture2DDepthList = null;        // depthテクスチャ.
        private int m_samplingCount = 24;                        // サンプリング数.

        private Vector3 [] m_samplingPosList = null;             // サンプリング位置のリスト (basePosからの差分).

        private int m_curP = 4;              // サンプリングのカレントの参照する位置.
        private float m_curBlend = 0.0f;     // サンプリングのカレントのブレンド値.

        private bool m_firstF = true;
        private float m_firstTime = -1.0f;

        // Use this for initialization
        void Start () {
            basePos = transform.position;
            CreateTexture2DList();

            // 背景球を作成.
            m_CreateBackgroundSphere();
        }
        
        // Update is called once per frame
        void Update () {
            if (m_firstTime < 0.0f) {
                m_firstTime = Time.time;
            }
            if (Time.time - m_firstTime > 1.0f) {
                if (m_firstF) {
                    prevPos = basePos = transform.position;
                    m_firstF = false;
                    Debug.Log("basePos " + basePos);
                }
            }
            m_UpdateBackgroundTexture();
        }

        void OnDestroy () {
            if (m_backgroundSphereMat != null) {
                Destroy(m_backgroundSphereMat);
            }
            if (m_backgroundSphere != null) {
                GameObject.Destroy(m_backgroundSphere);
            }
            if (m_blurMat != null) {
                Destroy(m_blurMat);
            }
        }

        /**
         * 背景球を作成.
         */
        private void m_CreateBackgroundSphere () {
            if (m_backgroundSphereMat == null) {
                // 以下、ビルドして実行する時にShaderを読み込めるように
                // Shader.FindではなくResources.Load<Shader>を使用している.
                Shader shader = Resources.Load<Shader>("Shaders/panoramaSphereSpaceMovement");
                m_backgroundSphereMat = new Material(shader);
            }
            if (m_backgroundSphere == null) {
                Mesh mesh = Resources.Load<Mesh>("Objects/backgroundSphere_vr360");
                m_backgroundSphere = new GameObject("panorama360Sphere");

                MeshRenderer meshRenderer = m_backgroundSphere.AddComponent<MeshRenderer>();
                MeshFilter meshFilter = m_backgroundSphere.AddComponent<MeshFilter>();
                meshRenderer.shadowCastingMode = ShadowCastingMode.Off;
                meshRenderer.receiveShadows    = false;
                meshRenderer.material = m_backgroundSphereMat;
                meshFilter.mesh = mesh;

                m_backgroundSphere.transform.localScale = new Vector3(radius, radius, radius);
                m_backgroundSphere.transform.position = this.transform.position;
 
                // Y軸中心の回転角度.
                Quaternion currentCameraRot = this.transform.rotation;
                float cRotY = currentCameraRot.eulerAngles.y;
                m_backgroundSphere.transform.rotation = Quaternion.Euler(0, cRotY + 90, 0);
            }
        }

        /**
        * 中心と周囲の8方向の位置でのパノラマをResourcesより読み込む.
        */
        void CreateTexture2DList () {
            if (m_blurMat == null) {
                // 以下、ビルドして実行する時にShaderを読み込めるように
                // Shader.FindではなくResources.Load<Shader>を使用している.
                Shader shader = Resources.Load<Shader>("Shaders/Blur");
                m_blurMat = new Material(shader);
            }

            m_samplingCount = 24;

            m_Texture2DList = new Texture2D[m_samplingCount];
            m_Texture2DDepthList = new RenderTexture[m_samplingCount];

            // RGBテクスチャ.
            for (int i = 0, iPos = 0; i < m_samplingCount; ++i, iPos += 1) {
                m_Texture2DList[i] = Resources.Load<Texture2D>("VR180/room/capture_" + (iPos).ToString());
            }

            for (int i = 0, iPos = 0; i < m_samplingCount; ++i, iPos += 1) {
                Texture2D tex2D = Resources.Load<Texture2D>("VR180/room/depth/capture_" + (iPos).ToString());

                int width  = tex2D.width;
                int height = tex2D.height;
                int width2  = width;
                int height2 = height;

                if (width2 >= 2048) {
                    width2 /= 2;
                    height2 /= 2;
                }

                m_Texture2DDepthList[i] = new RenderTexture(width2, height2, 0, RenderTextureFormat.ARGBFloat);
                m_Texture2DDepthList[i].filterMode = FilterMode.Point;
                m_Texture2DDepthList[i].Create();

                // ブラーをかける.
                RenderTexture.active = m_Texture2DDepthList[i];
                m_blurMat.SetTexture("_MainTex", tex2D);
                m_blurMat.SetInt("_TextureWidth", width);
                m_blurMat.SetInt("_TextureHeight", height);
                Graphics.Blit(null, m_Texture2DDepthList[i], m_blurMat);
            }
        }

        /**
        * 背景テクスチャを更新.
        */
        private void m_UpdateBackgroundTexture () {
            if (m_backgroundSphere == null || m_backgroundSphereMat == null) return;

            if (m_samplingPosList == null && !m_firstF) {
                // オリジナルの回転行列.
                Quaternion qRotY = Quaternion.Euler(0.0f, -rotationY, 0.0f);
                Matrix4x4 rotYMat = Matrix4x4.Rotate(qRotY);

                float dist = Vector3.Distance(startPos, endPos);
                Debug.Log("move distance " + dist.ToString());

                endPos   = rotYMat.MultiplyVector(endPos - startPos) + basePos;
                startPos = basePos;

                // 位置情報.
                m_samplingPosList = new Vector3[m_samplingCount + 1];

                {
                    Vector3 ddP = (endPos - startPos) / (float)(m_samplingCount - 1);
                    Vector3 wPos = startPos;
                    for (int i = 0; i < m_samplingCount; ++i) {
                        m_samplingPosList[i] = wPos;
                        wPos += ddP;
                    }
                }

                // 開始をbasePos2の位置にする.
                if (true) {
                    Vector3 basePos2 = m_samplingPosList[m_curP];
                    for (int i = 0; i < m_samplingCount; ++i) {
                        m_samplingPosList[i] = m_samplingPosList[i] - basePos2 + basePos;
                    }
                }
            }
            if (m_samplingPosList != null) {
                Vector3 curCameraPos = transform.position;

                int minPos = -1;
                float minBlend = 0.0f;
                float minADist = -1.0f;

                {
                    float maxAltitudeDist = 1.0f;
                    for (int i = 0; i < m_samplingCount - 1; ++i) {
                        Vector3 p1 = m_samplingPosList[i];
                        Vector3 p2 = m_samplingPosList[i + 1];

                        // p1-p2の直線とcurCameraPosでできる垂線位置を計算.
                        float aPos  = 0.0f;
                        float aDist = 0.0f;
                        if (!MathUtil.CalcPerpendicular(p1, p2, curCameraPos, ref aPos, ref aDist)) continue;
                        if (aPos < 0.0f || aPos > 1.0f) continue;
                        if (aDist > maxAltitudeDist) continue;
                        if (minPos < 0 || minADist > aDist) {
                            minPos = i;
                            minBlend = aPos;
                            minADist = aDist;
                        }
                    }
                }

                if (minPos >= 0) {
                    m_curP     = minPos;
                    m_curBlend = minBlend;
                }
            }

            // 静止画のパラメータを渡す.
            m_backgroundSphereMat.SetVector("_BasePos", new Vector4(basePos.x, basePos.y, basePos.z, 0.0f));
            m_backgroundSphereMat.SetVector("_PrevPos", new Vector4(prevPos.x, prevPos.y, prevPos.z , 0.0f));
            m_backgroundSphereMat.SetVector("_CurrentPos", new Vector4(transform.position.x, transform.position.y, transform.position.z , 0.0f));

            // サンプリングの位置.
            // 画像は+Xから-Xに移行している.
            Vector3 pos1 = (m_samplingPosList != null) ? m_samplingPosList[m_curP] : Vector3.zero;
            Vector3 pos2 = (m_samplingPosList != null) ? m_samplingPosList[m_curP + 1] : Vector3.zero;
            m_backgroundSphereMat.SetVector("_Pos1", new Vector4(pos1.x, pos1.y, pos1.z , 0.0f));
            m_backgroundSphereMat.SetVector("_Pos2", new Vector4(pos2.x, pos2.y, pos2.z , 0.0f));

            prevPos = transform.position;

            m_backgroundSphereMat.SetTexture("_Tex1", m_Texture2DList[m_curP]);
            m_backgroundSphereMat.SetTexture("_Tex2", m_Texture2DList[m_curP + 1]);
            m_backgroundSphereMat.SetTexture("_TexDepth1", m_Texture2DDepthList[m_curP]);
            m_backgroundSphereMat.SetTexture("_TexDepth2", m_Texture2DDepthList[m_curP + 1]);
            m_backgroundSphereMat.SetFloat("_BlendV", m_curBlend);
            m_backgroundSphereMat.SetFloat("_Intensity", intensity);
            m_backgroundSphereMat.SetFloat("_CameraNearPlane", 0.1f);
            m_backgroundSphereMat.SetFloat("_CameraFarPlane", 100.0f);

            m_backgroundSphereMat.SetInt("_DepthTextureWidth", m_Texture2DDepthList[m_curP].width);
            m_backgroundSphereMat.SetInt("_DepthTextureHeight", m_Texture2DDepthList[m_curP].height);
            m_backgroundSphereMat.SetInt("_SpatialInterpolation", spatialInterpolation ? 1 : 0);            
        }
    }
}

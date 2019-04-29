/**
 * 数値演算関数.
 */
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Panorama180View {
    public class MathUtil {
        /**
         * p1-p2の直線に、cPosからおろした垂線位置を計算.
         * @param[in]  p1    直線の始点.
         * @param[in]  p2    直線の終点.
         * @param[in]  cPos  対象点.
         * @param[out] aPos  p1-p2を1.0としたときの位置.
         * @param[out] aDist 垂線の長さ.
         */
        static public bool CalcPerpendicular (Vector3 p1, Vector3 p2, Vector3 cPos, ref float aPos, ref float aDist) {
            Vector3 retV = Vector3.zero;
            float fMin = (float)(1e-6);

            Vector3 vDir = p2 - p1;
            float len1 = Vector3.Distance(p1, p2);
            if (len1 < fMin) return false;
            vDir = vDir / len1;

            Vector3 vDir2 = cPos - p1;
            float len2 = Vector3.Distance(cPos, p1);
            if (len2 < fMin) {
                aPos  = 0.0f;
                aDist = 0.0f;
                return true;
            }
            vDir2 = vDir2 / len2;

            // p1-p2の直線上にあるか.
            float angleV = Vector3.Dot(vDir, vDir2);
            if (Mathf.Abs(angleV) >= 1.0f - fMin) {
                aPos = len2 / len1;
                if (angleV < 0.0f) {
                    aPos = -aPos;
                    aDist = 0.0f;
                    return true;
                }
            }

            float len3 = angleV * len2;
            aPos  = len3 / len1;
            aDist = Vector3.Distance(vDir * len3 + p1, cPos);
            return true;
        }
    }
}

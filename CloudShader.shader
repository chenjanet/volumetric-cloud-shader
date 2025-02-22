Shader "Custom/CloudShader"
{
    Properties
    {
        _SDFTex ("SDF Texture", 3D) = "white" {}
        _MainTex ("Texture", 2D) = "white" {}
        _NoiseTex ("Noise Texture", 2D) = "white" {}
        _BlueNoise ("Blue Noise Texture", 2D) = "white" {}
        _NoiseScale ("Noise Scale", Float) = 1.0
        _CloudDensity ("Cloud Density", Range(0, 2)) = 1.0
        _FadeStart ("Fade Start", Range(0.0, 1.0)) = 0.3
        _FadeEnd ("Fade End", Range(0.0, 1.0)) = 0.5
        _DebugSDF ("Debug SDF", Integer) = 0
        _SDFStrength ("SDF Strength", Range(1, 5)) = 3.0
        _NoiseStrength ("Noise Strength", Range(0, 1)) = 0.3
        _CloudSpeed ("Cloud Speed", Range(0, 2)) = 0.5
        _SunDirection ("Sun Direction", Vector) = (1,0,0) 
    }
    
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 100
        
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };
            
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 screenPos : TEXCOORD1;
                float3 objectSpaceViewDir : TEXCOORD2;
                float3 objectPos : TEXCOORD3;
                float4 grabPos : TEXCOORD4;
            };

            UNITY_DECLARE_SCREENSPACE_TEXTURE(_CameraOpaqueTexture);
            
            sampler2D _MainTex;
            float4 _MainTex_ST;

            sampler2D _NoiseTex;

            sampler2D _BlueNoise;

            sampler3D _SDFTex;

            float _NoiseScale;
            float _CloudDensity;

            float _FadeStart;
            float _FadeEnd;

            float _SDFStrength;
            float _NoiseStrength;

            float _CloudSpeed;

            bool _DebugSDF;

            float3 _SunDirection;
            
            #define MAX_STEPS 100
            #define MARCH_SIZE 0.1
            #define SUN_POSITION float3(1.0, 0.0, 0.0)
            
            float sampleSDF(float3 p) {
                float3 uv = p + 0.5;
                return tex3D(_SDFTex, uv).r;
            }

            float noise(float3 x) {
                float3 p = floor(x);
                float3 f = frac(x);
                float3 u = f * f * (3. - 2. * f);

                float2 uv = (p.xy + float2(37.0, 239.0) * p.z) + u.xy;
                float4 tex = tex2Dlod(_NoiseTex, float4((uv + 0.5) / 256.0, 0, 0));

                return lerp( tex.x, tex.y, u.z ) * 2.0 - 1.0;
            }

            float fbm(float3 p) {
                float3 q = p + _Time.x * 0.5 * float3(1.0, -0.2, -1.0);

                float f = 0.0;
                float scale = 0.5;
                float factor = 2.02;

                for (int i = 0; i < 6; i++) {
                    f += scale * noise(q * _NoiseScale);
                    q *= factor;
                    factor += 0.21;
                    scale *= 0.5;
                }

              return f;
            }

            float scene(float3 p)
            {
                float distance = sampleSDF(p);
                float f = fbm(p);

                float len = length(p);
                float falloff = 1.0 - smoothstep(_FadeStart, _FadeEnd, len * len); 

                float baseShape = -distance * _SDFStrength;
                float noise = f * _NoiseStrength;
    
                float blend = smoothstep(-0.15, 0.25, baseShape);
                float cloudShape = baseShape + noise * blend;

                cloudShape += pow(noise, 2.0) * 0.2;

                return cloudShape * _CloudDensity * falloff;
            }

            float4 raymarch(float3 rayOrigin, float3 rayDirection, float offset)
            {
                if (_DebugSDF) {
                    float depth = 0.0;
                    for (int i = 0; i < MAX_STEPS; i++)
                    {
                        float3 p = rayOrigin + depth * rayDirection;
                        float dist = sampleSDF(p);
            
                        if (dist < 0.001) {
                            // We hit the surface - return solid color
                            return float4(1.0, 1.0, 1.0, 1.0);
                        }
                        depth += max(0.01, abs(dist));
                    }
                    return float4(0.0, 0.0, 0.0, 0.0);
                }

                float depth = 0.0;
                depth += MARCH_SIZE * (1.0 + offset * 0.2);
                float3 p = rayOrigin + depth * rayDirection;
                float3 sunDirection = normalize(mul((float3x3)unity_WorldToObject, _WorldSpaceLightPos0.xyz));
                
                float4 res = float4(0.0, 0.0, 0.0, 0.0);
                
                for (int i = 0; i < MAX_STEPS; i++)
                {
                    float density = scene(p);
                    
                    if (density > 0.0)
                    {

                        float diffuse = clamp((scene(p) - scene(p + 0.3 * sunDirection)) / 0.3, 0.0, 1.0);
                        float3 lin = float3(0.60, 0.60, 0.75) * 1.1 + 0.8 * float3(1.0, 0.6, 0.3) * diffuse;
                        float4 color = float4(lerp(float3(1.0, 1.0, 1.0), float3(0.0, 0.0, 0.0), density), density);
                        color.rgb *= lin;
                        color.rgb *= color.a;

                        float transmittance = 1.0 - res.a;
                        res += color * transmittance;
                    }
                    
                    depth += MARCH_SIZE * (1.0 + offset * 0.1);
                    p = rayOrigin + depth * rayDirection;
                }
                
                return res;
            }
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.grabPos = ComputeGrabScreenPos(o.vertex);

                float3 objectSpaceViewPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1.0)).xyz;
                o.objectSpaceViewDir = normalize(objectSpaceViewPos - v.vertex.xyz);
                o.objectPos = v.vertex.xyz;
                return o;
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                float3 ro = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1.0)).xyz;
                float3 rd = normalize(i.objectPos - ro);

                float timeOffset = _Time.y * _CloudSpeed;
                timeOffset = frac(timeOffset);

                float2 pixelCoord = i.vertex.xy;
                float blueNoise = tex2D(_BlueNoise, pixelCoord / 1024.0).r;
                float offset = frac(blueNoise + timeOffset);

                float4 res = raymarch(ro, rd, offset);

                float2 grabUV = i.grabPos.xy / i.grabPos.w;
                float3 backgroundColor = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_CameraOpaqueTexture, grabUV).rgb;
                float3 finalColor = backgroundColor * (1.0 - res.a) + res.rgb;
                
                return float4(finalColor, res.a);
            }
            ENDCG
        }
    }
}

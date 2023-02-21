Shader "Toon/Team Fortress 2"
{
    Properties
    {   
        // Albedo
        [Header(Albedo)]
        [Space(10)]
        _MainTex ("Albedo", 2D) = "white" {} 
        _RampMap ("Ramp Map", 2D) = "white" {} 
        _MainColor ("Main Color", Color) = (1, 1, 1, 1)
        
        // Normal
        [Header(Normal)]
        [Space(10)]
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalScale ("Normal Scale", Float) = 1.0
        
        // Ambient Occlusion
        [Header(Ambient Occlusion)]
        [Space(10)]
        _AOMap ("Ambient Occlusion", 2D) = "white" {} 
        
        // Smoothness
        [Header(Specular)]
        [Space(10)]
        _SmoothnessMap ("Smoothness Map", 2D) = "white" {} 
        _SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        _FresnelSpecular ("Specular Scale", Range(0, 1)) = 1
        _KSpecular ("Specular Power", Range(2, 64)) = 64
        
        // Metal
        [Header(Metalness)]
        [Space(10)]
        _MetalMap ("Metal Map", 2D) = "white" {} 
        
        // Emission
        [Header(Emission)]
        [Space(10)]
        _EmissionMap ("Emission Map", 2D) = "white" {} 
        [HDR]_EmissionColor ("Emission Color", Color) = (0, 0, 0, 0)
        
        // Rim Light
        [Header(Rim Light)]
        [Space(10)]
        _RimLightColor ("Rim Light Color", Color) = (1, 1, 1, 1)
        _RimPower ("Rim Power", Range(1, 64)) = 4
    }
    SubShader
    {
        Tags {
            "RenderType"="Opaque"
            "RenderPipeLine"="UniversalRenderPipeline"
        }
        Cull Off
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
        TEXTURE2D(_RampMap);        SAMPLER(sampler_RampMap);
        TEXTURE2D(_NormalMap);        SAMPLER(sampler_NormalMap);
        TEXTURE2D(_AOMap);        SAMPLER(sampler_AOMap);
        TEXTURE2D(_SmoothnessMap);        SAMPLER(sampler_SmoothnessMap);
        TEXTURE2D(_MetalMap);        SAMPLER(sampler_MetalMap);
        TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);
        
        CBUFFER_START(UnityPerMaterial)
            half4 _MainTex_ST;
            half4 _RampMap_ST;
            half4 _MainColor;
            half4 _NormalMap_ST;
            half _NormalScale;
            half4 _AOMap_ST;
            half4 _SmoothnessMap_ST;
            half4 _SpecularColor;
            half _FresnelSpecular;
            half _KSpecular;
            half4 _MetalMap_ST;
            half _ShadowRange;
            half4 _EmissionMap_ST;
            half4 _EmissionColor;
            half4 _RimLightColor;
            half _RimPower;
        CBUFFER_END

        struct Attributes
        {
            half4 positionOS    : POSITION;
            half3 normalOS      : NORMAL;
            half2 uv            : TEXCOORD0;
            half4 vertexColor   : TEXCOORD1;
            half4 tangetOS      : TANGENT;
        };

        struct Varyings
        {
            half4 positionCS    : SV_POSITION;
            half3 positionWS    : POSITION_WS;
            half3 normalWS      : NORMAL_WS;
            half2 uv            : TEXCOORD0;
            half4 vertexColor   : TEXCOORD1;
            half4 tangentWS     : TANGENT_WS;
        };

        ENDHLSL

        Pass 
        {
            Tags{
                "LightMode"="UniversalForward"    
            }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragement _EMISSION

            real3 SH_indirectDiffuse(real3 normalWS, real AO)
            {
                real4 SHCoefficients[7];
                SHCoefficients[0] = unity_SHAr;
                SHCoefficients[1] = unity_SHAg;
                SHCoefficients[2] = unity_SHAb;
                SHCoefficients[3] = unity_SHBr;
                SHCoefficients[4] = unity_SHBg;
                SHCoefficients[5] = unity_SHBb;
                SHCoefficients[6] = unity_SHC;
                real3 color = SampleSH9(SHCoefficients, normalWS);
                return max(0, color) * AO;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
                const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normalOS);
                // get positive or negative normal signal (should be either 1 or -1)
                half sign = IN.tangetOS.w * GetOddNegativeScale();
                
                OUT.positionWS = vertex_position_inputs.positionWS;
                OUT.positionCS = vertex_position_inputs.positionCS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.vertexColor = IN.vertexColor;
                OUT.normalWS = vertex_normal_inputs.normalWS;
                OUT.tangentWS = half4(vertex_normal_inputs.tangentWS, sign);
                return OUT;
            }
            
            half4 frag(Varyings IN) : SV_Target
            {   
                // Direction Function
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv), _NormalScale);
                half3 biTangent = IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);
                half3 normalWS = mul(normalTS, half3x3(IN.tangentWS.xyz, biTangent, IN.normalWS));
                half3 viewDirWS = GetWorldSpaceViewDir(IN.positionWS);
                
                // Lighting Calculation
                Light mainLight = GetMainLight(); 
                half4 lightColor = half4(mainLight.color, 1); 
                half3 lightDir = normalize(mainLight.direction); 
                
                // Textures
                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _MainColor;
                half4 AOMap = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, IN.uv);
                half smoothness = 1 - SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, IN.uv);
                half metalMask = SAMPLE_TEXTURE2D(_MetalMap, sampler_MetalMap, IN.uv);
                half emissionMap = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, IN.uv);
                
                // Albedo
                half4 albedo = mainTex;
                half3 AO = 1;
                half3 indirectDiffuse = SH_indirectDiffuse(normalWS, AO);
                
                // Dot Product Function
                half ndotL = max(0, dot(normalWS, lightDir));
                half ndotH = max(0, dot(normalWS, normalize(viewDirWS + lightDir)));
                half ndotV = max(0, dot(normalWS, viewDirWS));
                half ndotU = max(0, dot(normalWS, (0, 1.0, 0)));
                
                // Lambert
                half lambert = ndotL;
                half halfLambert= saturate(lambert * 0.5 + 0.5);
                half halfLambertAO = AOMap * halfLambert;
                half4 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, half2(halfLambert, 0));
                half4 wrapDiffuseTerm = ramp * lightColor;

                //计算View Independent Lighting Terms
                half3 viewIndependentLightTerms = albedo * (indirectDiffuse+ wrapDiffuseTerm);

                // 计算View dependent Lighting Terms
                half halfVector = normalize(viewDirWS + lightDir);
                half3 specular = pow(ndotH, 2);
                half fresnel = pow(1 - dot(viewDirWS, halfVector), 5.0);
                fresnel += 0.5 * (1.0 - fresnel);
                half3 multiplePhongTerms = specular * fresnel * lightColor;
                half rim = 1.0 - saturate(ndotV);
                half3 dedicatedRimLighting = _RimLightColor * pow(rim, _RimPower);
                half3 viewDependentLightTerms = albedo * lightColor * max(multiplePhongTerms, dedicatedRimLighting);
                
                // Combine
                half3 color = viewIndependentLightTerms + viewDependentLightTerms;
                
                return half4(multiplePhongTerms, 1);
            }
            
            ENDHLSL
        }
    }
} 
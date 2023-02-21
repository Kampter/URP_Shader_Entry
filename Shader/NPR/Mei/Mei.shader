Shader "Toon/Mei"
{
    Properties
    {   
        // Albedo
        [Header(Albedo)]
        [Space(10)]
        _MainTex ("Albedo", 2D) = "white" {} 
        _MainColor ("Main Color", Color) = (1, 1, 1, 1)
        
        // Light Map
        [Header(LightMap)]
        [Space(10)]
        _LightMap ("LightMap", 2D) = "white" {} 
        _WrapDiffuse ("Wrap Diffuse (HalfLambert = 0.5)", Range(0, 1)) = 0.5
        _ShadeEdge0 ("Shade Edge 0", Range(0, 1)) = 0.2
        _ShadeEdge1 ("Shade Edge 1", Range(0, 1)) = 0.8
        
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
        
        // Outline 
        [Header(Outline)]
        [Space(10)]
        _OutlineWidth ("Outline Width", Float) = 0.1
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 0)
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
        TEXTURE2D(_LightMap);        SAMPLER(sampler_LightMap);
        TEXTURE2D(_NormalMap);        SAMPLER(sampler_NormalMap);
        TEXTURE2D(_AOMap);        SAMPLER(sampler_AOMap);
        TEXTURE2D(_SmoothnessMap);        SAMPLER(sampler_SmoothnessMap);
        TEXTURE2D(_MetalMap);        SAMPLER(sampler_MetalMap);
        TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);
        
        CBUFFER_START(UnityPerMaterial)
            half4 _MainTex_ST;
            half4 _LightMap_ST;
            half _WrapDiffuse;
            half _ShadeEdge0;
            half _ShadeEdge1;
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
            half _OutlineWidth;
            half4 _OutlineColor;
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
                "LightMode" = "UniversalForward"    
            }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragement _EMISSION

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
                half3 viewDirWS = GetViewForwardDir();
                
                // Lighting Calculation
                Light mainLight = GetMainLight(); 
                half4 lightColor = half4(mainLight.color, 1); 
                half3 lightDir = normalize(mainLight.direction); 
                
                // Textures
                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _MainColor;
                half4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, IN.uv).g;
                half4 AOMap = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, IN.uv);
                half smoothness = SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, IN.uv);
                half metalMask = SAMPLE_TEXTURE2D(_MetalMap, sampler_MetalMap, IN.uv);
                half emissionMap = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, IN.uv);
                
                // Albedo
                half4 albedo = mainTex;
                half4 ambient = half4(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w, 1.0);
                half4 vertexColor = IN.vertexColor.b; 
                
                // Dot Product Function
                half ndotLRaw = dot(viewDirWS, lightDir);
                half ndotL = max(0, ndotLRaw);
                half ndotH = max(0, dot(normalWS, normalize(viewDirWS + lightDir)));
                half ndotV = max(0, dot(normalWS, viewDirWS));
                half ndotU = max(0, dot(normalWS, (0, 1.0, 0)));
                
                // Lambert
                half lambert = ndotL;
                half halfLambert= saturate(lambert * 0.5 + 0.5);
                half halfLambertAO = AOMap * halfLambert;
                half warpLambert =(lambert * _WrapDiffuse + 1- _WrapDiffuse) + lightMap.g;
                half shadowStep = saturate(smoothstep(_ShadeEdge0, _ShadeEdge1, warpLambert));
                
                // Specular
                half fs = _FresnelSpecular;
                half4 spec = fs * pow(ndotH, smoothness);
                half4 specular = pow(spec, _KSpecular)* _SpecularColor * metalMask;
                
                // Rim Lighting
                half kr = 0.5;
                half fr = pow(1 - ndotV, 4);
                half4 rim = kr * fr * pow(spec, _RimPower);

                // Dedicated Rim Lighting 
                half4 aV = half(1);
                half4 dedicatedRimLighting = ndotU * fr * kr * aV;
                
                // Multiple Phong Terms
                half ks = 1;
                half4 multiplePhongTerms = ks * lightColor * max(specular, rim);
                half4 viewDependentLightTerms = multiplePhongTerms + dedicatedRimLighting;

                // Fake SSS
                half4 emission = emissionMap * _EmissionColor;
                
                // Combine
                half4 diffuse = albedo * shadowStep;
                
                half4 color = diffuse + emission + viewDependentLightTerms;
                return albedo;
            }
            
            ENDHLSL
        }
//        Pass
//        {
//            Name "Outline"
//            Tags { 
//                   "LightMode" = "SRPDefaultUnlit" 
//            }
//            Cull Front
//                    
//            HLSLPROGRAM
//            #pragma vertex vert
//            #pragma fragment frag
//            
//            Varyings vert(Attributes IN) 
//            {
//                
//                Varyings OUT;
//                const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
//                const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normalOS);
//                
//                OUT.positionCS = vertex_position_inputs.positionCS;
//                OUT.normalWS = vertex_normal_inputs.normalWS;
//                
//                IN.positionOS += IN.tangetOS * 0.001 * _OutlineWidth;//顶点色a通道控制粗细
//                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
//                half3 normal = normalize(mul((float3x3)UNITY_MATRIX_IT_MV, OUT.normalWS));
//                float2 offset = TransformWorldToViewNormal(normal.xy);
//                OUT.positionCS.xy += offset * OUT.positionCS.z * _OutlineWidth;
//                OUT.uv = IN.uv;
//                OUT.vertexColor = IN.vertexColor;
//                return OUT;
//            }
//
//            half4 frag(Varyings IN) : SV_TARGET 
//            { 
//                return IN.vertexColor * _OutlineColor;
//            }
//            
//            ENDHLSL
//        }
    }
} 
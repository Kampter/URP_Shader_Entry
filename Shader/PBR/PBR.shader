Shader "Toon/PBR"
{
    Properties
    {   
        // Albedo
        [Header(Albedo)]
        [Space(10)]
        _MainTex ("Albedo", 2D) = "white" {} 
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
        
        // Metal
        [Header(Metalness)]
        [Space(10)]
        _MetalMap ("Metal Map", 2D) = "white" {} 
        
        // Emission
        [Header(Emission)]
        [Space(10)]
        _EmissionMap ("Emission Map", 2D) = "white" {} 
        [HDR]_EmissionColor ("Emission Color", Color) = (0, 0, 0, 0)
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
        TEXTURE2D(_NormalMap);        SAMPLER(sampler_NormalMap);
        TEXTURE2D(_AOMap);        SAMPLER(sampler_AOMap);
        TEXTURE2D(_SmoothnessMap);        SAMPLER(sampler_SmoothnessMap);
        TEXTURE2D(_MetalMap);        SAMPLER(sampler_MetalMap);
        TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);
        
        CBUFFER_START(UnityPerMaterial)
            half4 _MainTex_ST;
            half4 _MainColor;
            half4 _NormalMap_ST;
            half _NormalScale;
            half4 _AOMap_ST;
            half4 _SmoothnessMap_ST;
            half4 _MetalMap_ST;
            half4 _EmissionMap_ST;
            half4 _EmissionColor;
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

            half Function_D(half ndotH, half roughness)
            {
                half a2 = roughness * roughness;
                half ndotH2 = ndotH * ndotH;
                half nom = a2;
                half denom = (ndotH2 * (a2 - 1.0) + 1.0);
                denom = PI * denom * denom;
                return nom/denom;
            }

            half GeometrySchlickGGX(half ndotV, half k)
            {
                float nom   = ndotV;
                float denom = ndotV * (1.0 - k) + k;

                return nom / denom;
            }

            half GeometrySmith(half ndotV, half ndotL, half k)
            {
                float ggx1 = GeometrySchlickGGX(ndotV, k);
                float ggx2 = GeometrySchlickGGX(ndotL, k);
                return ggx1 * ggx2;
            }

            half Function_G(half ndotV, half ndotL, half k)
            {
                return GeometrySmith(ndotV, ndotL, k);
            }
            
            // calculate F0
            half3 Calculate_F0(half3 albedo, half metalness)
            {
                half3 F0 = 0.04;
                F0 = lerp(F0, albedo, metalness);
                return F0;
            }
            
            half3 Function_F(half ndotV, half3 albedo, half metalness)
            {
                half3 F0 = Calculate_F0(albedo, metalness);
                return F0 + (1.0 - F0) * pow(1.0 - ndotV, 5.0);
            }
            
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
            
            half3 IndirectSpecular(half reflectVector, half roughness, half AO)
            {
                half mip = PerceptualRoughnessToMipmapLevel(roughness);
                half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));
                half3 irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                return irradiance * AO;
            }
            
            // Indirect Function F
            half3 EnvironmentBRDFSpecular(half roughness, half3 specular, half fresnelTerm, half grazingTerm)
            {
                half surfaceReduction = 1.0 / (roughness * roughness + 1.0);
                return half3(surfaceReduction * lerp(specular, grazingTerm, fresnelTerm));
            }

            half4 frag(Varyings IN) : SV_Target
            {   
                // Direction Function
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv), _NormalScale);
                half3 biTangent = IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);
                half3 normalWS = mul(normalTS, half3x3(IN.tangentWS.xyz, biTangent, IN.normalWS));
                half3 viewDirWS = GetWorldSpaceViewDir(IN.positionWS);
                half3 reflectVector = reflect(-viewDirWS, normalWS);
                
                // Lighting Calculation
                Light mainLight = GetMainLight(); 
                half4 mainLightColor = half4(mainLight.color, 1); 
                half3 mainLightDir = normalize(mainLight.direction);
                half mainLightAtten = mainLight.distanceAttenuation;
                
                // Textures
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _MainColor;
                half4 AO = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, IN.uv);
                //half smoothness = SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, IN.uv);
                half metalness = SAMPLE_TEXTURE2D(_MetalMap, sampler_MetalMap, IN.uv);
                half emissionMap = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, IN.uv);
                half3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w) * albedo * AO;
                
                // Dot Product Function
                half ndotL = max(0, dot(normalWS, mainLightDir));
                half ndotH = max(0, dot(normalWS, normalize(viewDirWS + mainLightDir)));
                half ndotV = max(0, dot(normalWS, viewDirWS));

                // Fake SSS
                half4 emission = emissionMap * _EmissionColor;
                
                // Direct BRDF = Lambertian + Direct Specular
                // direct specular
                half smoothness = 1;
                half roughness = 1 - smoothness;
                half functionD = Function_D(ndotH, roughness);
                // remap roughness to k value
                half kDirect = pow(roughness + 1, 2) / 8;
                half direct_functionG = Function_G(ndotV, ndotL, kDirect);
                half3 functionF = Function_F(ndotV, albedo, metalness);
                half3 nominator = functionD * direct_functionG * functionF;
                half demoninator = 4.0 * ndotV * ndotL + 0.001;
                half3 specular = nominator / demoninator;
                // Lambertian
                half3 kS = functionF; 
                half3 kD = half3(1.0, 1.0, 1.0) - kS;
                kD *= 1.0 - metalness;
                // Render Equation
                half3 radiance = mainLightColor * mainLightAtten;
                half3 Lo = (kD * albedo / PI + kS * specular) * radiance * ndotL * AO;
                half3 directColor = ambient + Lo;
                // Indirect BRDF
                // Indirect diffuse
                half3 indirectDiffuse = SH_indirectDiffuse(normalWS, AO);
                half3 indirectColor = indirectDiffuse * albedo;
                // Indirect Specualr
                half NoV = saturate(dot(normalWS, viewDirWS));
                half fresnelTerm = Pow4(1.0 - NoV);
                half oneMinusReflectivity = OneMinusReflectivityMetallic(metalness);
                half reflectivity = half(1.0) - oneMinusReflectivity;
                half grazingTerm = saturate(reflectivity + smoothness);
                half3 indirectSpecular = IndirectSpecular(reflectVector, roughness, AO);
                half3 brdfSpecular = Calculate_F0(albedo, metalness);
                indirectColor += AO * indirectSpecular * EnvironmentBRDFSpecular(roughness, brdfSpecular, fresnelTerm, grazingTerm);

                half3 color = directColor + indirectColor + emission;
                return half4(functionF, 1);
            }
            
            ENDHLSL
        }
    }
} 
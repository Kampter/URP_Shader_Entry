Shader "Custom/BumpMap"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _BaseMap ("Main Texture", 2D) = "white"{}
        _SpecColor ("Specular Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _Smoothness ("Gloss", range(8, 256)) = 20
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Scale", Float) = 1.0
    }
    SubShader
    {
        Tags {
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalRenderPipeline" 
            "LightMode" = "UniversalForward"
            "ShaderModel"="4.5"
        }
        LOD 100
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                half4 positionOS : POSITION;
                half3 normal : NORMAL;
                half4 tangetOS : TANGENT;
                half2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                half4 positionCS : SV_POSITION;
                half3 positionWS : POSITION_WS;
                half2 uv : TEXCOORD0;
                half3 normalWS : NORMAL_WS;
                half4 tangentWS : TANGENT_WS;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseMap_ST;
                half4 _BumpMap_ST;
                half4 _BaseColor;
                half4 _SpecColor;
                half _Smoothness;
                half _BumpScale;
            CBUFFER_END
            
            Varyings vert (Attributes IN)
            {
                const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
                const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normal);
                // get positive or negative normal signal (should be either 1 or -1)
                half sign = IN.tangetOS.w * GetOddNegativeScale();

                Varyings OUT;
                OUT.positionWS = vertex_position_inputs.positionWS;
                OUT.positionCS = vertex_position_inputs.positionCS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = vertex_normal_inputs.normalWS;
                OUT.tangentWS = half4(vertex_normal_inputs.tangentWS, sign);
                return OUT;
            }
            
            half4 frag (Varyings IN) : SV_Target
            {
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv), _BumpScale);
                half3 biTangent = IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);
                half3 normalWS = mul(normalTS, half3x3(IN.tangentWS.xyz, biTangent, IN.normalWS));
                
                Light mainLight = GetMainLight();
                half3 lightColor = mainLight.color;
                half3 lightDir = normalize(mainLight.direction);
                half3 viewDirWS = normalize(GetCameraPositionWS() - IN.positionWS);
                
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                half3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w) * albedo;
                
                half3 diffuse = saturate(dot(lightDir, normalWS)) * lightColor * ambient;
                half3 halfDir = normalize(viewDirWS + lightDir);
                half3 specular = pow(saturate(dot(normalWS, halfDir)), _Smoothness) * lightColor * saturate(_SpecColor);
                
                half4 finalColor = half4(ambient + diffuse + specular, 1.0);
                return finalColor;
            }
            ENDHLSL
        }
    }
}

 Shader "Custom/Lambert"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Main Texture", 2D) = "white"{}
    }
    SubShader
    {
        Tags {
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalRenderPipeline" 
            "LightMode" = "UniversalForward"
            "ShaderModel"="4.5"
        }

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
                half2 uv : TEXCOORD0;
                half3 normalWS : NORMAL_WS;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _BaseMap_ST;
            CBUFFER_END
            
            Varyings vert (Attributes IN)
            {
                const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
                const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normal);
                
                Varyings OUT;
                OUT.positionCS = vertex_position_inputs.positionCS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = vertex_normal_inputs.normalWS;
                return OUT;
            }
            
            half4 frag (Varyings IN) : SV_Target
            {
                Light mainLight = GetMainLight();
                half3 lightColor = mainLight.color;
                half3 lightDir = mainLight.direction;

                half3 normalWS = IN.normalWS;
                // NdotL
                half lightAtten = dot(lightDir, normalWS) * 0.5 + 0.5;
                //half lightAtten = saturate(dot(lightDir, normalWS));
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                half3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
                half3 diffuse = tex * lightAtten * lightColor * ambient;
                half4 finalColor = half4(diffuse, 1.0);
                
                return finalColor;
            }
            ENDHLSL
        }
    }
}

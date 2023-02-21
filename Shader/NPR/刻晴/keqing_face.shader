Shader "Toon/keqing_face"
{
    Properties
    {
        [Header(Settings)]
        [Space(10)]
        // Day or Night
        _IsNight ("is Night ? Day(0.5) or Night(0)", Range(0, 0.5))= 0.5
        
        // Textures
        [Header(Textures)]
        [Space(10)]
        _MainTex ("Albedo", 2D) = "white" {} 
        _FaceLightMap ("SDF LightMap", 2D) = "white" {}
        _FaceShadow ("Face Shadow", 2D) = "white" {}
        
        // Smooth
        [Header(Smoothness)]
        [Space(10)]
        _ShadowSmooth ("_BodyShadowSmooth", Range(0, 1)) = 0.5
        _WrapDiffuse ("Wrap Diffuse (HalfLambert = 0.5)", Range(0, 1)) = 0.5
        
        // Emission
        [Header(Emission)]
        [Space(10)]
        _EmissionIntensity("Emission Intensity", Float) = 1
        [HDR]_EmissionColor ("_Emission Color", Color) = (1, 1, 1, 1)
        
        // Face Shadow
        [Header(Face Shadow)]
        [Space(10)]
        [HDR]_FaceShadowColor ("Face Shadow Color", Color) = (0, 0, 0, 0)
    }
    SubShader
    {
        Tags {
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalRenderPipeline" 
            "ShaderModel"="4.5"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
        TEXTURE2D(_LightMap);       SAMPLER(sampler_LightMap);
        TEXTURE2D(_ShadowRamp);       SAMPLER(sampler_ShadowRamp);
        TEXTURE2D(_FaceLightMap);       SAMPLER(sampler_FaceLightMap);
        TEXTURE2D(_FaceShadow);       SAMPLER(sampler_FaceShadow);
        
        CBUFFER_START(UnityPerMaterial)
            half4 _MainTex_ST;
            half4 _faceLightMap_ST;
            half4 _FaceShadow_ST;
            half _ShadowSmooth;
            half _WrapDiffuse;
            half _IsNight;
            half _EmissionIntensity;
            half4 _EmissionColor;
            half4 _FaceShadowColor;
            half _ClipValue;
        CBUFFER_END

        struct Attributes
        {
            half4 positionOS    : POSITION;
            half3 normal        : NORMAL;
            half2 uv            : TEXCOORD0;
            half4 vertexColor   : TEXCOORD1;
        };

        struct Varyings
        {
            half4 positionCS    : SV_POSITION;
            half3 positionWS    : POSITION_WS;
            half3 normalWS      : NORMAL_WS;
            half2 uv            : TEXCOORD0;
            half4 vertexColor   : TEXCOORD1;
        };
        ENDHLSL
        
        Pass
        {
            Tags {"LightMode" = "UniversalForward"}
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            
            Varyings vert (Attributes IN)
            {
                const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
                const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normal);

                Varyings OUT;
                OUT.positionCS = vertex_position_inputs.positionCS;
                OUT.positionWS = vertex_position_inputs.positionWS;
                OUT.normalWS = vertex_normal_inputs.normalWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.vertexColor = IN.vertexColor;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // Direction Function
                half3 viewDirWS = GetWorldSpaceViewDir(IN.positionWS);
                half3 normalWS = IN.normalWS;
                
                // Light Calculation
                Light mainLight = GetMainLight(); 
                half4 lightColor = half4(mainLight.color, 1); //获取主光源颜色
                half3 lightDir = normalize(mainLight.direction); //主光源方向

                // Albedo
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv); 
                half4 vertexColor = IN.vertexColor; //顶点色

                // Texture Sampling
                // lightmap
                // R channel = Specular Mask
                // G channel = AO Map
                // B channel = Roughness
                // A channel = Emission Mask
                // 灰度1.0 ： 皮肤质感/头发质感（头发的部分是没有皮肤的）
                // 灰度0.7 ： 丝绸/丝袜
                // 灰度0.5 ： 金属/金属投影
                // 灰度0.3 ： 软的物体
                // 灰度0.0 ： 硬的物体
                half4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, IN.uv); 

                // Dot Product Function
                half ndotL = max(0, dot(normalWS, lightDir));
                half ndotH = max(0, dot(normalWS, normalize(viewDirWS + lightDir)));
                half ndotV = max(0, dot(normalWS, viewDirWS));
                half ndotU = max(0, dot(normalWS, (0, 1.0, 0)));
                
                //lambert
                half lambert = ndotL;
                half lambertAO = lambert * saturate(lightMap.g * 2);
                half lambertRampAO = smoothstep(0, _ShadowSmooth, lambertAO);

                // using vertex color as an offset to adjust half lambert sampling
                half halfLambertAO = saturate(lambertRampAO * _WrapDiffuse + 1 - _WrapDiffuse);
                half vertexOffset = step(0.5, vertexColor) == 1 ? vertexColor : 1 - vertexColor;
                half adjustedHalfSampler = saturate(halfLambertAO * vertexOffset);
                
                // Day (0.5) or Night(0)
                half dayOrNight = (1 - step(0.1, _IsNight)) * 0.5 + 0.03;
                half4 diffuse = lerp(0.9, lightColor, dayOrNight) * albedo;

                // Emission (Fake SSS)
                half emissionMask = albedo.a;
                emissionMask *= step(0.1, lightMap.a);
                // abs((frac(_Time.y * 0.5) - 0.5) * 2)
                half4 emission = albedo * emissionMask * _EmissionIntensity * _EmissionColor;

                // SDF
                // 人物朝向 Get character orientation
                half3 up = float3(0,1,0);  
                half3 front = TransformObjectToWorldDir(float4(0.0,0.0,1.0,1.0));
                half3 right = cross(up, front);
                //左右阴影图 Sample flipped face light map
                half2 rightFaceUV = float2(-IN.uv.x, IN.uv.y);
                half4 faceShadowR = SAMPLE_TEXTURE2D(_FaceLightMap, sampler_FaceLightMap, rightFaceUV);
                half4 faceShadowL = SAMPLE_TEXTURE2D(_FaceLightMap, sampler_FaceLightMap, IN.uv);
                //灯光朝向和灯光vector不一致，逆时针转90，投影后要归一化，不然长度会小于1
                half s = sin(90 * (PI/180.0f));
                half c = cos(90 * (PI/180.0f));
                half2x2 rMatrix = float2x2(c, -s, s, c);    
                half2 realLDir = normalize(mul(rMatrix,lightDir.xz));
                half realFDotL = dot(normalize(front.xz), realLDir);
                half realRDotL =  dot(normalize(right.xz), realLDir);
                //通过RdotL决定用哪张阴影图
                half shadowTex = realRDotL < 0? faceShadowL: faceShadowR;
                //获取当前像素的阴影阈值
                half shadowMargin = shadowTex.r;
                //判断是否在阴影中
                half inShadow = -0.5 * realFDotL + 0.5 > shadowMargin;
                half2 shadowUV = half2(inShadow * mainLight.shadowAttenuation - 0.06, 0.4 + dayOrNight);
                half faceShadowMask = 1 - SAMPLE_TEXTURE2D(_FaceShadow, sampler_FaceShadow, shadowUV).a;
                half shadow = lerp(_FaceShadowColor, diffuse, inShadow) * albedo * faceShadowMask;
                diffuse += shadow * 0.2;                
                
                half4 color = diffuse + emission;
                return color;
            }
            ENDHLSL
        }
        Pass 
    	{
			Name "OutLine"
			Tags {"LightMode" = "SRPDefaultUnlit"}
			Cull front
			HLSLPROGRAM
			#pragma vertex vert  
			#pragma fragment frag
			
			Varyings vert(Attributes IN) {
                float4 scaledScreenParams = GetScaledScreenParams();
                float ScaleX = abs(scaledScreenParams.x / scaledScreenParams.y);//求得X因屏幕比例缩放的倍数
        
				Varyings OUT;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(IN.normal);
                float3 normalCS = TransformWorldToHClipDir(normalInput.normalWS);//法线转换到裁剪空间
                float2 extendDis = normalize(normalCS.xy) * (0.1 * 0.01);//根据法线和线宽计算偏移量
                extendDis.x /=ScaleX ;//由于屏幕比例可能不是1:1，所以偏移量会被拉伸显示，根据屏幕比例把x进行修正
                OUT.positionCS = vertexInput.positionCS;
                OUT.positionCS.xy +=extendDis;
				return OUT;
			}
			
			half4 frag(Varyings IN) : SV_Target {
				return float4(0, 0, 0, 1);
			}
			
			ENDHLSL
		}
        pass 
    	{
			Tags{ "LightMode" = "ShadowCaster" }
            ZWrite On
    		ZTest LEqual
            HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag

    		Varyings vert (Attributes IN)
            {
            	const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);

            	Varyings OUT;
                OUT.positionCS = vertex_position_inputs.positionCS;
    			OUT.positionWS = vertex_position_inputs.positionWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);;
                return OUT;
            }
            
            half4 frag (Varyings IN) : SV_Target
            {
            	half3 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
            	half4 diffColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
            	clip(diffColor - _ClipValue);
            	return 0;
            }
			ENDHLSL

        }
    }
}

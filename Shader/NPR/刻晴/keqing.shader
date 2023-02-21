Shader "Toon/keqing"
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
        _LightMap ("LightMap", 2D) = "white" {}
        _ShadowRamp ("Shadow Ramp", 2D) = "white" {}
        _MetalMap ("Metal Map", 2D) = "white" {}
        _SpecualrRamp ("Specualr Ramp", 2D) = "white" {}
        
        // Specular
        [Header(Specular)]
        [Space(10)]
        _MetalIntensity ("Metal Specular Intensity", Range(0, 10)) = 0.5
        
        // Smooth
        [Header(Shadow)]
        [Space(10)]
        _ShadowSmooth ("_Body Shadow Smooth", Range(0, 1)) = 0.5
        _WrapDiffuse ("Wrap Diffuse (HalfLambert = 0.5)", Range(0, 1)) = 0.5
        
        // Emission
        [Header(Emission)]
        [Space(10)]
        _EmissionIntensity("Emission Intensity", Float) = 1
        [HDR]_EmissionColor ("_Emission Color", Color) = (1, 1, 1, 1)
        
        // Rim Light
    	[Header(Rim Light)]
        [Space(10)]
        _RimWidth ("Rim Width", Range(0, 1)) = 1
        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)
    	_RimThreshold ("Rim Threhold", Range(0, 1)) = 0.5
        _RimIntensity ("Rim Intensity", Range(0, 5)) = 1
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
            TEXTURE2D(_MetalMap);       SAMPLER(sampler_MetalMap);
            TEXTURE2D(_SpecualrRamp);       SAMPLER(sampler_SpecualrRamp);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
            
            CBUFFER_START(UnityPerMaterial)
                half4 _MainTex_ST;
                half4 _LightMap_ST;
                half4 _ShadowRamp_ST;
                half4 _MetalMap_ST;
                half4 _SpecualrRamp_ST;
                half _MetalIntensity;
                half _ShadowSmooth;
                half _WrapDiffuse;
                half _IsNight;
                half _EmissionIntensity;
                half4 _EmissionColor;
                half4 _FaceShadowColor;
                half _RimWidth;
                half4 _RimColor;
                half _RimSmoothness;
				half _RimIntensity;
				half _RimThreshold;
                half _ClipValue;;
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
                half3 positionVS    : POSITION_VS;
                half4 positionNDC   : POSITION_NDC;
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
                OUT.positionNDC = vertex_position_inputs.positionNDC;
                OUT.positionWS = vertex_position_inputs.positionWS;
                OUT.positionVS = vertex_position_inputs.positionVS;
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
                half3 normalVS = TransformWorldToView(normalWS);
                
                // Light Calculation
                Light mainLight = GetMainLight(); 
                half4 lightColor = half4(mainLight.color, 1); //获取主光源颜色
                half3 lightDir = normalize(mainLight.direction); //主光源方向

                // Dot Product Function
                half ndotL = max(0, dot(normalWS, lightDir));
                half ndotH = max(0, dot(normalWS, normalize(viewDirWS + lightDir)));
                half ndotV = max(0, dot(normalWS, viewDirWS));
                
                // Albedo
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv); 
                half4 vertexColor = IN.vertexColor; //顶点色
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
    
                // diffuse = ramp + adjusted half lambert + AO
                half rampV = saturate(lightMap.a * 0.45 + dayOrNight);
                half2 rampUV = half2(adjustedHalfSampler, rampV);
                
                //half4 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, half2(halfLambert, 0));
                half4 shadowRamp = SAMPLE_TEXTURE2D(_ShadowRamp, sampler_ShadowRamp, rampUV);
                half4 diffuse = lerp(shadowRamp, lightColor, adjustedHalfSampler) * albedo;

                // Emission (Fake SSS)
                half emissionMask = albedo.a;
                emissionMask *= step(0.65, lightMap.a);
                // half time =  abs((frac(_Time.y * 0.5) - 0.5) * 2);
                half4 emission = albedo * lightColor * emissionMask * _EmissionIntensity * _EmissionColor;
                
                // Metal Specular
                half metalMask = step(0.95, lightMap.r);
                half3 cameraForward = -viewDirWS;
                half3 viewUpDir = mul(UNITY_MATRIX_I_V, half4(0, 1, 0, 0)).xyz;
                half3 cameraRight = SafeNormalize(cross(viewUpDir, cameraForward));
                half3 cameraUp = SafeNormalize(cross(cameraForward, cameraRight));
                half2 metalMapUV = mul(half3x3(cameraRight, cameraUp, cameraForward), normalWS).xy * 0.49 + 0.5;
                half4 metalMap = SAMPLE_TEXTURE2D(_MetalMap, sampler_MetalMap, metalMapUV);
                half4 metalSpecular = _MetalIntensity * metalMap * metalMask * albedo;
                
                // specular = Metal + Non-metal
                half Ks = 0.96;
                half  SpecularPow = exp2(lightMap.r);//这里乘以0.5是为了扩大高光范围
                half  SpecularNorm = (SpecularPow + 8.0) / 8.0;
                half4 SpecularColor = albedo * lightMap.g;
                half SpecularContrib = SpecularNorm * pow(ndotH, SpecularPow);
                half4 nonMetalSpecular = SpecularColor * SpecularContrib * Ks * lightMap.b;
                half4 specular =  nonMetalSpecular + metalSpecular;

            	// Rim
                half4 color = diffuse * (1-step(0.95, lightMap.r)) + specular + emission;
                return color;
            }
            ENDHLSL
        }
    	pass
    	{
    		name "RimLight"
    		Tags {"LightMode" = "DepthOnly"}
    		
    		HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

    		half4 TransformHClipToViewPortPos(half4 positionCS)
			{
        		half4 o = positionCS * 0.5f;
        		o.xy = half2(o.x, o.y * _ProjectionParams.x) + o.w;
        		o.zw = positionCS.zw;
        		return o / o.w;
			}
            
            Varyings vert (Attributes IN)
            {
                const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
                const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normal);

                Varyings OUT;
                OUT.positionCS = vertex_position_inputs.positionCS;
                OUT.positionWS = vertex_position_inputs.positionWS;
        		OUT.positionVS = vertex_position_inputs.positionVS;
        		OUT.positionNDC = vertex_position_inputs.positionNDC;
                OUT.normalWS = vertex_normal_inputs.normalWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.vertexColor = IN.vertexColor;
                return OUT;
            }

    		half4 frag (Varyings IN) : SV_Target
    		{
    			half3 normalWS = IN.normalWS;
				half3 normalVS = TransformWorldToViewDir(normalWS, true);
    			half3 positionVS = IN.positionVS;
    			half4 positionNDC = IN.positionNDC;

    			half3 samplePositionVS = half3(positionVS.xy + normalVS.xy * _RimWidth, positionVS.z);
    			half4 samplePositionCS = TransformWViewToHClip(samplePositionVS); 
				half4 samplePositionVP = TransformHClipToViewPortPos(samplePositionCS);

				half depth = positionNDC.z / positionNDC.w;
				half linearEyeDepth = LinearEyeDepth(depth, _ZBufferParams);
				half offsetDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, samplePositionVP).r; 
				half linearEyeOffsetDepth = LinearEyeDepth(offsetDepth, _ZBufferParams);
				half depthDiff = linearEyeOffsetDepth - linearEyeDepth;
				half rimIntensity = step(_RimThreshold, depthDiff);

    			half3 viewDirWS = GetWorldSpaceViewDir(IN.positionWS);
				half rimRatio = 1 - saturate(dot(viewDirWS, normalWS));
				rimRatio = pow(rimRatio, exp2(lerp(4.0, 0.0, 1)));
				rimIntensity = lerp(0, rimIntensity, rimRatio);
    			
				half4 rimLight = lerp(half4(0, 0, 0, 1), _RimColor, rimIntensity);
    			
    			return rimLight;
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
                half4 scaledScreenParams = GetScaledScreenParams();
                half ScaleX = abs(scaledScreenParams.x / scaledScreenParams.y);
        
				Varyings OUT;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(IN.normal);
                half3 normalCS = TransformWorldToHClipDir(normalInput.normalWS);
                half2 extendDis = normalize(normalCS.xy) * (0.1 * 0.01);
                extendDis.x /=ScaleX ;
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
			Tags {"LightMode" = "ShadowCaster"}
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

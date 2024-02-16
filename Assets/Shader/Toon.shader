Shader"Custom/Toon"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
        _ShadowColor ("Shadow Color", Color) = (0,0,0,1)
        _ShadowThreshold ("Shadow Threshold", Range(0, 1)) = 0.5
        
        _OutlineWidth ("Outline Width", Range(0, 10)) = 1
        
        _RimColor("Rim Color", Color) = (1,1,1,1)
        _RimThickness ("Rim Thickness", Range(0, 10)) = 1
        _RimThreshold ("Rim Threshold", Range(0, 10)) = 2
    }
HLSLINCLUDE
    
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

    TEXTURE2D(_BaseMap);
    SAMPLER(sampler_BaseMap);
float4 _BaseMap_ST;
float4 _BaseMap_TexelSize;
    
half4 _Color;
half4 _ShadowColor;
half _ShadowThreshold;
    
half _RimThickness;
half _RimThreshold;
half4 _RimColor;

half _OutlineWidth;

float4 _CameraDepthTexture_TexelSize;

float4 TransformHClipToNormalizedScreenPos(float4 positionCS)
{
    float4 o = positionCS * 0.5f;
    o.xy = float2(o.x, o.y * _ProjectionParams.x) + o.w;
    o.zw = positionCS.zw;
    return o / o.w;
}

half SampleOffsetDepth(float3 positionVS, float2 offset)
{
        // カメラとの距離やカメラのFOVで見た目上の輪郭の太さが変わらないように、オフセットをViewSpaceで計算する
    float3 samplePositionVS = float3(positionVS.xy + offset, positionVS.z);
    float4 samplePositionCS = TransformWViewToHClip(samplePositionVS);
    float4 samplePositionVP = TransformHClipToNormalizedScreenPos(samplePositionCS);
        
    float offsetDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, samplePositionVP).r;
    return offsetDepth;
}

half SobelFilter(float3 positionWS, float thickness)
{
    float3x3 sobel_x = float3x3(-1, 0, 1, -2, 0, 2, -1, 0, 1);
    float3x3 sobel_y = float3x3(-1, -2, -1, 0, 0, 0, 1, 2, 1);

    float edgeX = 0;
    float edgeY = 0;

    float3 positionVS = TransformWorldToView(positionWS);

    UNITY_UNROLL

    for (int x = -1; x <= 1; x++)
    {
        UNITY_UNROLL

        for (int y = -1; y <= 1; y++)
        {
            float2 offset = float2(x, y) * thickness;
            half depth = SampleOffsetDepth(positionVS, offset);
            depth = LinearEyeDepth(depth, _ZBufferParams);
                
            float intensity = depth;
            edgeX += intensity * sobel_x[x + 1][y + 1];
            edgeY += intensity * sobel_y[x + 1][y + 1];
        }
    }

        // エッジの強度を計算
    float edgeStrength = length(float2(edgeX, edgeY));
    edgeStrength = step(_RimThreshold, edgeStrength);
    return float4(edgeStrength, edgeStrength, edgeStrength, 1);
}

ENDHLSL
    SubShader
{
    Tags{ "RenderType"="Opaque"
}

        Pass
        {
Cull Back
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Varyings
{
    float4 positionHCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normalWS : TEXCOORD1;
    float3 viewDirWS : TEXCOORD2;
    float2 screenPos : TEXCOORD3;
    float3 positionWS : TEXCOORD4;
};

Varyings vert(Attributes IN)
{
    Varyings OUT;

    VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS);
    OUT.positionHCS = positionInputs.positionCS;
    OUT.positionWS = positionInputs.positionWS;
    OUT.uv = IN.uv;

    VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS);
    OUT.normalWS = normalInputs.normalWS;

    OUT.viewDirWS = GetWorldSpaceViewDir(positionInputs.positionWS);

    OUT.screenPos = positionInputs.positionNDC.xy / positionInputs.positionNDC.w;
                
    return OUT;
}

half4 frag(Varyings IN) : SV_Target
{
    half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);

    Light light = GetMainLight();
                
    half3 normalWS = IN.normalWS;
    half3 lightDirWS = light.direction;

                // Lambert
    half halfLambert = dot(normalWS, lightDirWS) * 0.5 + 0.5;
    half intensity = step(_ShadowThreshold, halfLambert);
    color.rgb = color.rgb * lerp(_ShadowColor, _Color, intensity);

                // Rim (Fresnel)
                /*
                half fresnel = saturate(dot(normalWS, normalize(IN.viewDirWS)));
                half rim = 1.0 - fresnel;
                rim = step(_RimThreshold, rim);
                */
                
                // Rim (Sobel Filter)
    half rimThickness = _RimThickness * halfLambert * 0.1;
    half rim = SobelFilter(IN.positionWS, rimThickness);
                
    color.rgb += rim * _RimColor.rgb;
                
    return color;
}
            ENDHLSL
        }
        
        Pass
        {
Name"Outline"
            Tags
{
                "LightMode" = "Outline"
}
            
ZWrite On

Cull Front
            
            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex OutlineVertex
            #pragma fragment OutlineFragment

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Varyings
{
    float4 positionHCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

Varyings OutlineVertex(Attributes IN)
{
    Varyings OUT;

    float3 positionOS = IN.positionOS.xyz + normalize(IN.normalOS) * _OutlineWidth * 0.001;
    VertexPositionInputs positionInputs = GetVertexPositionInputs(positionOS);
    OUT.positionHCS = positionInputs.positionCS;
    OUT.uv = IN.uv;

    return OUT;
}

half4 OutlineFragment(Varyings IN) : SV_Target
{
    return half4(0, 0, 0, 1);
}

            ENDHLSL   
        }
        
        Pass
        {
Name"DepthOnly"
            Tags
{
                "LightMode" = "DepthOnly"
}

ZWrite On

ColorMask R

Cull Back

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

struct Attributes
{
    float4 position : POSITION;
    float2 texcoord : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
};

Varyings DepthOnlyVertex(Attributes input)
{
    Varyings output = (Varyings) 0;
    output.positionCS = TransformObjectToHClip(input.position.xyz);
    return output;
}

half DepthOnlyFragment(Varyings input) : SV_TARGET
{
    return input.positionCS.z;
}
            ENDHLSL
        }
    }
}
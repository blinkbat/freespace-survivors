pub const scene_vs =
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec3 vertexNormal;
    \\in vec2 vertexTexCoord;
    \\in vec2 vertexTexCoord2;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matModel;
    \\uniform mat4 matNormal;
    \\out vec3 pos;
    \\out vec3 normal;
    \\out vec2 uv;
    \\out vec4 color;
    \\out float material;
    \\void main() {
    \\    pos = vec3(matModel * vec4(vertexPosition, 1.0));
    \\    normal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
    \\    uv = vertexTexCoord;
    \\    color = vertexColor;
    \\    material = vertexTexCoord2.x;
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
;
pub const scene_fs =
    \\#version 330
    \\in vec3 pos;
    \\in vec3 normal;
    \\in vec2 uv;
    \\in vec4 color;
    \\in float material;
    \\uniform vec3 eye;
    \\uniform vec3 sun;
    \\uniform mat4 lightVP;
    \\uniform sampler2D shadowMap;
    \\uniform vec3 lightPos[4];
    \\uniform vec4 lightColor[4];
    \\uniform vec4 flash;
    \\uniform float opacity;
    \\uniform float jungle;
    \\uniform float time;
    \\out vec4 finalColor;
    \\float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    \\float shadow(vec3 n) {
    \\    vec4 p = lightVP * vec4(pos, 1.0);
    \\    vec3 s = p.xyz / p.w * 0.5 + 0.5;
    \\    if (any(lessThan(s, vec3(0.002))) || any(greaterThan(s, vec3(0.998)))) return 1.0;
    \\    float bias = max(0.00007, 0.00035 * (1.0 - dot(n, sun)));
    \\    float lit = 0.0;
    \\    for(int x=-1; x<=1; ++x) for(int y=-1; y<=1; ++y)
    \\        lit += s.z - bias <= texture(shadowMap, s.xy + vec2(x,y)/2048.0).r ? 1.0 : 0.0;
    \\    return lit/9.0;
    \\}
    \\void main() {
    \\    vec3 base = color.rgb;
    \\    if (opacity < 1.0 && hash(floor(gl_FragCoord.xy)) > opacity) discard;
    \\    if (material > 0.5 && material < 2.5) {
    \\        vec2 pixel = floor(uv * 8.0);
    \\        vec2 panel = mod(pixel, 32.0);
    \\        float seam = min(panel.x, panel.y) < 1.0 ? 0.46 : 1.0;
    \\        float bolts = (panel.x == 2.0 || panel.x == 29.0) && (panel.y == 2.0 || panel.y == 29.0) ? 1.55 : 1.0;
    \\        base *= seam * bolts * (0.87 + hash(pixel) * 0.23);
    \\        base *= 0.88 + hash(floor(uv / 4.0)) * 0.24;
    \\        if (material > 1.5) base *= mod(floor((pixel.x + pixel.y) / 6.0), 2.0) < 1.0 ? 0.18 : 1.0;
    \\    }
    \\    vec3 n = normalize(normal);
    \\    if (material > 5.5 && material < 6.5) {
    \\        vec2 stoneUV = abs(n.y)>0.6 ? pos.xz : (abs(n.x)>0.6 ? pos.zy : pos.xy);
    \\        vec2 tile = floor(stoneUV*0.65);
    \\        vec2 block = mod(tile+vec2(floor(tile.y/12.0)*5.0,0.0),vec2(20.0,12.0));
    \\        base *= (min(block.x,block.y)<1.0 ? 0.65 : 1.0)*(0.8+hash(tile)*0.35);
    \\        float moss = smoothstep(0.35,0.75,hash(floor(stoneUV*0.2))+n.y*0.25);
    \\        base = mix(base,base*vec3(0.55,0.85,0.45),moss*0.65);
    \\    }
    \\    if (material > 6.5 && material < 7.5) {
    \\        float grain=hash(floor(pos.xz*1.5)+floor(pos.y*0.08));
    \\        base *= 0.65+grain*0.6;
    \\    }
    \\    if (material > 7.5 && material < 9.5) {
    \\        base *= 0.82+hash(floor(pos.xz*2.0)+floor(pos.y))*0.25;
    \\    }
    \\    if (material > 9.5) {
    \\        float ripple=sin(pos.x*0.35+time*1.8+sin(pos.z*0.24))*sin(pos.z*0.5-time);
    \\        base = mix(base,vec3(0.32,0.66,0.54),smoothstep(0.78,1.0,ripple)*0.5);
    \\        n=normalize(n+vec3(ripple*0.1,0.0,sin(pos.x*0.3+time)*0.12));
    \\    }
    \\    vec3 albedo = pow(base, vec3(2.2));
    \\    float diffuse = max(dot(n, sun), 0.0) * shadow(n);
    \\    vec3 lit = albedo * (mix(vec3(0.20,0.25,0.36),vec3(0.40,0.52,0.43),jungle) + vec3(1.5,1.4,1.25)*diffuse);
    \\    if(material>9.5) lit += vec3(0.25,0.38,0.3)*pow(1.0-max(dot(n,normalize(eye-pos)),0.0),3.0);
    \\    for (int i=0; i<4; ++i) {
    \\        vec3 d = lightPos[i] - pos;
    \\        float distance = length(d);
    \\        float falloff = pow(max(0.0, 1.0-distance/lightColor[i].a), 2.0);
    \\        lit += albedo * lightColor[i].rgb * falloff * (0.20 + 2.8*max(dot(n, normalize(d)),0.0));
    \\    }
    \\    if (material > 2.5 && material < 3.5) lit = albedo * 3.5;
    \\    if (material > 3.5 && material < 4.5) lit *= 0.82 + 0.18*hash(floor(pos.xy*1.7)+floor(pos.z));
    \\    if (material > 4.5 && material < 5.5) lit += base*0.6*pow(1.0-max(dot(n,normalize(eye-pos)),0.0),3.0);
    \\    lit = mix(lit, flash.rgb * 3.2, flash.a);
    \\    vec3 mapped = lit / (vec3(1.0) + lit * 0.6);
    \\    vec3 outputColor = pow(max(mapped,vec3(0.0)), vec3(1.0/2.2));
    \\    float fog = 1.0 - exp(-length(eye-pos)*mix(0.00012,0.0017,jungle));
    \\    finalColor = vec4(mix(outputColor, mix(vec3(0.035,0.055,0.09),vec3(0.37,0.57,0.49),jungle), fog), 1.0);
    \\}
;
pub const depth_vs =
    \\#version 330
    \\in vec3 vertexPosition;
    \\uniform mat4 mvp;
    \\void main() { gl_Position = mvp * vec4(vertexPosition,1.0); }
;
pub const depth_fs =
    \\#version 330
    \\out vec4 finalColor;
    \\void main() { finalColor = vec4(1.0); }
;
pub const sky_fs =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\uniform vec3 forward;
    \\uniform vec3 right;
    \\uniform vec3 up;
    \\uniform vec2 lens;
    \\uniform float jungle;
    \\out vec4 finalColor;
    \\float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
    \\float cloudNoise(vec2 p) {
    \\    vec2 i=floor(p), f=fract(p);
    \\    f=f*f*(3.0-2.0*f);
    \\    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
    \\}
    \\void main() {
    \\    vec2 p = fragTexCoord * 2.0 - 1.0;
    \\    vec3 d = normalize(forward + right*p.x*lens.x*lens.y - up*p.y*lens.y);
    \\    if (jungle > 0.5) {
    \\        vec3 col=mix(vec3(0.58,0.70,0.53),vec3(0.13,0.39,0.39),pow(max(d.y,0.0),0.55));
    \\        vec2 cloudUV=d.xz/max(0.12,d.y+0.12)*1.8;
    \\        float clouds=cloudNoise(cloudUV)*0.6+cloudNoise(cloudUV*2.1+17.0)*0.28+cloudNoise(cloudUV*4.3)*0.12;
    \\        col=mix(col,vec3(0.85,0.84,0.69),smoothstep(0.48,0.72,clouds)*smoothstep(0.0,0.12,d.y)*0.65);
    \\        vec3 sunDir=normalize(vec3(-0.5,0.8,0.6));
    \\        float sunDot=max(dot(d,sunDir),0.0);
    \\        col+=vec3(0.55,0.43,0.21)*pow(sunDot,40.0);
    \\        col=mix(col,vec3(1.0,0.96,0.72),smoothstep(0.9988,0.9993,sunDot));
    \\        vec3 moonDir=normalize(vec3(0.65,0.37,-0.7));
    \\        float moon=dot(d,moonDir);
    \\        if(moon>0.991) {
    \\            float edge=smoothstep(0.991,0.992,moon);
    \\            col=mix(col,vec3(0.56,0.68,0.57)*(0.65+0.25*sin(d.y*180.0)),edge*0.62);
    \\        }
    \\        float az=atan(d.z,d.x);
    \\        float ridge=0.018+0.032*sin(az*9.0)+0.02*sin(az*21.0);
    \\        col=mix(col,vec3(0.32,0.49,0.41),1.0-smoothstep(ridge-0.007,ridge,d.y));
    \\        col=mix(col,vec3(0.37,0.57,0.49),1.0-smoothstep(-0.08,0.04,d.y));
    \\        finalColor=vec4(col,1.0);
    \\        return;
    \\    }
    \\    vec2 sphere = vec2(atan(d.z,d.x)/6.2831853, asin(clamp(d.y,-1.0,1.0))/3.14159);
    \\    float cloud = pow(max(0.0,0.5+0.5*sin(d.x*4.0+d.y*7.0+sin(d.z*5.0))),3.0);
    \\    vec3 col = vec3(0.009,0.016,0.029) + cloud * vec3(0.024,0.025,0.041);
    \\    vec2 grid = sphere * vec2(1700.0,850.0);
    \\    vec2 id = floor(grid);
    \\    vec2 cell = fract(grid);
    \\    float star = hash(id);
    \\    if (star > 0.995) {
    \\        float spot = 1.0 - smoothstep(0.10,0.38,length(cell-0.5));
    \\        col += mix(vec3(0.42,0.60,0.75),vec3(0.93,0.73,0.48), hash(id+31.0))*spot;
    \\    }
    \\    finalColor = vec4(col,1.0);
    \\}
;
pub const post_fs =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\uniform sampler2D texture0;
    \\uniform vec2 texel;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec3 color = texture(texture0,fragTexCoord).rgb;
    \\    vec3 glow = vec3(0.0);
    \\    for(int x=-2; x<=2; ++x) for(int y=-2; y<=2; ++y) {
    \\        vec3 c = texture(texture0,fragTexCoord+vec2(x,y)*texel*1.5).rgb;
    \\        glow += max(c-vec3(0.72),vec3(0.0));
    \\    }
    \\    vec2 p=fragTexCoord*2.0-1.0;
    \\    finalColor=vec4((color+glow*0.055)*(1.0-0.13*dot(p,p)),1.0);
    \\}
;

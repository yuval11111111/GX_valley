uniform shader iChunk;
uniform float2 iChunkSize;
uniform float2 iChunkOffset;
uniform float iFrame;

//1D hash function
half hash1(float p)
{
	return fract(cos(p*12.98)*3956.4);
}
//1D hash function
half hash1(float2 p)
{
	return fract(cos(p.x*12.98+p.y*69.42)*3956.4);
}
//2D hash function
half2 hash2(float2 p)
{
	return fract(cos(p*float2x2(12.98,78.37,69.42,13.14))*3956.4);
}
//1D hash function
half4 hash4(float2 p)
{
	return fract(cos(p.x*float4(12.98,78.37,69.42,13.14)+p.y*float4(59.67,14.59,11.26,73.38))*3956.4);
}
//Value noise (bi-cubic)
half value(float2 p)
{
	float2 f = floor(p);
	float2 s = p-f;
	s *= s*(3-s*2);
	const float2 o = float2(0,1);
	return mix(mix(hash1(f+o.xx),hash1(f+o.yx),s.x),mix(hash1(f+o.xy),hash1(f+o.yy),s.x),s.y);
}
half clouds(float2 p, float time)
{
	float T = 0;
	half n = 0;
	float w = 1;
	float t = 0;
	float2 q = p;
	for(float i = 0;i<3;i++)
	{
		q *= float2x2(-0.8,0.6,0.6,0.8)*2.5;
		half v = value(q-time/sqrt(w)+T*2);
		T += v;
		n += v*w;
		t += w;
		w *= 0.4;
	}
	return n/t;
}

half particle(float2 p, float time, half type,float transition)
{
	float a = 0;
	float2 q = p;
	float2x2 t = float2x2(1);
	
	for(float i = 0;i<4;i++)
	{
		float2 s = -float2(0,time*(8+i));
		t *= float2x2(-0.8,0.6,0.6,0.8)*1.1;
		float2 cell = ceil((q+s)*t/2);
		float2 part = mod((q+s+float2(.2,.1)*cos(cell.yx+i*float2(7,1)+iFrame*2))*t,2)-1+cos(cell.yx/.3-i)*.3;
		
		half4 rand = hash4(cell/100);
		float angle = atan(part.y,part.x)*6+iFrame*(rand.x-0.5)*50;
		float shape = mix(1-length(t*part*float2(10,1)),
		exp(cos(angle)*.9+cos(angle*3)*(rand.y*.3+.7)+2+2*rand.y-length(part)*30+cos(length(part)*120+rand.z*6.2831)*rand.w/2), type)
		* smoothstep(0.0, 0.2, transition-rand.z*0.1);
		a = max(a,shape);
	}
	return a;
}
half4 main(float2 xy)
{
	//Weather cycle time (in seconds)
	const float CYCLE = 30;
	
	//Cloud parameters
	const float CLOUD_SCALE = 800;
	const half CLOUD_SPEED = 0.2;
	const half CLOUD_ALPHA = 0.8;
	
	//Particle parameters
	const half PARTICLE_ALPHA = 0.6;
	const float PARTICLE_SCALE = 200;
	const half PARTICLE_SNOW_SPEED = 0.1;
	const half PARTICLE_RAIN_SPEED = 1;
	
	//Lightning parameters.
	const half4 LIGHTNING_COLOR = half4(1.3,1,1.3,0);
	const float LIGHTNING_RATE = 2;
	
	//Add scroll offset
	float2 p = xy+iChunkOffset;
	half2 uv = p/iChunkSize*2-1;
	//Sample base texture
	half4 color = iChunk.eval(xy);
	
	//Compute cycle time
	float cycle_time = iFrame/CYCLE;
	//Transitionary period between weather cycles
	half transition = abs(fract(cycle_time-0.5) - 0.5);
	//Smoothed transition for clouds
	half smooth_transtion = smoothstep(0, 0.2, transition);
	//Generate random weather index
	float weather = floor(hash1(floor(cycle_time))*4);
	//0 = clear
	//1 = snow
	//2 = rain
	//3 = thunder
	
	//Color tints change with weather
	half4 tint = half4(0.9, 1.0, 1.0, 1.0);
	if (weather == 1) tint = half4(0.7, 0.7, 0.7, 1.0);
	if (weather == 2) tint = half4(1.2, 1.1, 1.0, 1.0);
	if (weather == 3) tint = half4(1.4, 1.3, 1.2, 1.0);
	
	//Swap between rain and snow particles
	float part_type = weather==1? 1 : 0;
	//Compute particle animation time
	float part_time = (weather==1? PARTICLE_SNOW_SPEED : PARTICLE_RAIN_SPEED)*iFrame;
	//Compute particle alpha
	half part_alpha = weather==0 ? 0 : particle(p / PARTICLE_SCALE, part_time, part_type, transition);
	
	//Cloudiness value (lower = more clouds)
	half cloudiness = 2.0 - weather*0.6*smooth_transtion;
	//Sample cloud noise function
	half cloud_value = clouds(p / CLOUD_SCALE, CLOUD_SPEED * iFrame);
	//Compute cloud alpha using the cloudiness level and distance from the screen edge
	half cloud_alpha = sqrt(cloud_value) * pow(abs(uv.x), cloudiness);
	//Combined particle and cloud alpha value
	half alpha = max(part_alpha * PARTICLE_ALPHA, cloud_alpha * CLOUD_ALPHA);
	//Blend with base color
	color = mix(color, half4(pow(half3(alpha), half3(1.1,0.95,0.8)), 1), alpha * alpha);
	
	//Generate pseudo-random lighting flashes
	half lightning = smoothstep(0.01, 0, abs(cos(iFrame*LIGHTNING_RATE+cos(iFrame*LIGHTNING_RATE/2.13))-0.99));
	//Compute distance to lighting bolt
	float lightning_dist = abs(xy-iChunkSize*hash1(ceil(iFrame))+cloud_value*400).x;
	//Add flash only (in thunderstorms)
	if (weather == 3) color += LIGHTNING_COLOR * pow(lightning_dist,0.4*lightning-0.5)*lightning;
	
	//Apply color tinting
	return pow(color, 1+(tint-1)*smooth_transtion);
}
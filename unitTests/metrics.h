#ifndef METRICS_H
#define METRICS_h

typedef struct 
{
	float avgStep;
	float avgMaxWarp;
	float runTime;	// in ms
} Metrics_t;

/* aggregate metrics from a kernel run with Nthreads
	step_counts; array of step counts for each thread */
static inline Metrics_t aggregate_metrics(int *step_counts, int Nthreads){
	// for (int i=0; i<Nthreads; i++) printf("%d, %d\n", i, step_counts[i]);
	Metrics_t out;
	// calculate avg of step counts 
	unsigned long Sum_Step = 0;
	for (int i=0; i<Nthreads; ++i)
		Sum_Step+=step_counts[i];
	out.avgStep = (float)Sum_Step/Nthreads;
	
	// calculate avg of max warp
	unsigned long Sum_MaxWarp = 0; int max_warp = 0;
	for (int i=0; i<Nthreads; ++i){
		if (i%32==0) max_warp = 0;	// reset for new warp
		if (step_counts[i]>max_warp) max_warp = step_counts[i];
		if (i%32==31 || i==Nthreads-1)	// end of warp, write result
			Sum_MaxWarp+=max_warp;
	}
	int Nwarps = ceil((float)Nthreads/32);
	out.avgMaxWarp = (float)Sum_MaxWarp/Nwarps;	
	return out;
}


/* taking a sample average on metrics
 */
static inline Metrics_t sample_average(Metrics_t *metrics_arr, int len){
	Metrics_t output;
	output.avgStep = 0; output.avgMaxWarp = 0; output.runTime = 0;
	for (int k=0; k<len; k++){
		output.avgStep += metrics_arr[k].avgStep/len;
		output.avgMaxWarp += metrics_arr[k].avgMaxWarp/len;
		output.runTime += metrics_arr[k].runTime/len;
	}
	return output;
}



/* kernel wall timing */ 
struct KernelTiming{
	cudaEvent_t start, stop;

	void startKernelTiming(){
		cudaEventCreate(&start);
		cudaEventCreate(&stop);
		cudaEventRecord(start, 0);
	}

	float stopKernelTiming(){
		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		float time;
		cudaEventElapsedTime(&time, start, stop);
		cudaEventDestroy(start);
		cudaEventDestroy(stop);
		return time;
	}
};






#endif
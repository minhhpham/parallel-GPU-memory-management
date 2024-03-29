#include "parallelPage.cuh"
#include "metrics.h"

static __device__ void fillPage(void *page){
	char *ptr = (char*)page;
	for (int i=0; i<PAGE_SIZE; i++)
		ptr[i] = 1;
}

/* Kernel to get 1 page with Random Walk, record step counts */
__global__ void CollabRW_get1page_kernel(int Nthreads, int *d_step_counts){
	int tid = blockIdx.x*blockDim.x + threadIdx.x;
	if (tid<Nthreads){
		int step_counts;
		int *tmp = d_step_counts? &step_counts : 0;
		int pageID = getPageCollabRW(tmp);
		if (d_step_counts) d_step_counts[tid] = step_counts;
		// mem check
		void *page = pageAddress(pageID);
		fillPage(page);
	}
}


/* Execute one kernel of N threads, each gets 1 page with Random Walk
	input: Nthreads: 		number of threads
	return: *avgStep:		average of step counts across all threads
			*avgMaxWarp:	average of Max of Warp across all warps
			*runTime:		total run time (s)
 */
Metrics_t runCollabRW(int Nthreads, int NFree){
	// allocate metrics array on host
	int *h_step_counts = (int*)malloc(10000*sizeof(int));
	// allocate metrics array on gpu
	int *d_step_counts;
	gpuErrchk( cudaMalloc((void**)&d_step_counts, 10000*sizeof(int)) );

	// run kernel until get to NFree
	resetBufferCollabRW();
	// printNumPagesLeftCollabRW();
	int NGets = TOTAL_N_PAGES - NFree;
	for (int i=0; i<(NGets/5000); i++){
		CollabRW_get1page_kernel <<< ceil((float)5000/32), 32 >>> (5000, 0);
		gpuErrchk( cudaPeekAtLastError() );
		gpuErrchk( cudaDeviceSynchronize() );
	}
	// printNumPagesLeftCollabRW();
	for (int i=0; i<(NGets-(NGets/5000)*5000)/1000; i++){
		CollabRW_get1page_kernel <<< ceil((float)1000/32), 32 >>> (1000, 0);
		gpuErrchk( cudaPeekAtLastError() );
		gpuErrchk( cudaDeviceSynchronize() );
	}
	printNumPagesLeftCollabRW();

	// execute kernel;
	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start, 0);
	CollabRW_get1page_kernel <<< ceil((float)Nthreads/32), 32 >>> (Nthreads, d_step_counts);
	gpuErrchk( cudaPeekAtLastError() );
	gpuErrchk( cudaDeviceSynchronize() );
	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	float total_time;
	cudaEventElapsedTime(&total_time, start, stop);
	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	// copy metrics to host
	gpuErrchk( cudaMemcpy(h_step_counts, d_step_counts, Nthreads*sizeof(int), cudaMemcpyDeviceToHost) );

	// aggregate metrics and return
	Metrics_t out = aggregate_metrics(h_step_counts, Nthreads);
	out.runTime = total_time;
	free(h_step_counts); cudaFree(d_step_counts);
	return out;
}


int main(int argc, char const *argv[])
{
	gpuErrchk(cudaSetDevice(0));
	/* command descriptions */
	if(argc>1 && ((strncmp(argv[1], "-h", 2) == 0) || (strncmp(argv[1], "-help", 4) == 0))){
		fprintf(stderr, "USAGE: ./unitTestCollabRW [options]\n");
		fprintf(stderr, "OPTIONS:\n");
		// fprintf(stderr, "\t -pn, --pageNum <pageNum>\n");
		// fprintf(stderr, "\t\t Total Pages, default is 1000000\n\n");

		fprintf(stderr, "\t -tn, --threadNum <threadsNum>\n");
		fprintf(stderr, "\t\t Total threads that are asking pages, default is 5000\n\n");

		// fprintf(stderr, "\t -lp, --leftPage <leftPageNum>\n");
		// fprintf(stderr, "\t\t Pages left in the system, default is all pages free \n\n");
	}

	/* parse options */
	int Nthreads=0;
	for (int i=0; i<argc; i++){
		if((strncmp(argv[i], "-tn", 3) == 0) || (strcmp(argv[i], "--threadNum") == 0))
			Nthreads = atoi(argv[i]);

	}
	if (Nthreads==0) Nthreads = 5000;


	/* initialize system, all pages free, parameters defined in parallelPage.cuh */
	fprintf(stderr, "initializing page system ... \n");
	initPagesCollabRW();
	// printNumPagesLeftCollabRW();

	/* repeat getpage with Random Walk */
	int AvailablePages = 100000;
	Nthreads = 9951;
	Metrics_t metrics;
	printf("T,N,A,Average_steps,Average_Max_Warp,Time(ms)\n");
	for (AvailablePages=4190000; AvailablePages<=4190000; AvailablePages+=10000){
		int N_SAMPLES = 1; // take average across 100 samples
		metrics.avgStep = 0; metrics.avgMaxWarp = 0; metrics.runTime = 0;
		Metrics_t metrics_1;
		for (int s=0; s<N_SAMPLES; s++){
			// run kernel to get 1 page for each thread
			metrics_1 = runCollabRW(Nthreads, AvailablePages);
			metrics.avgStep += metrics_1.avgStep;
			metrics.avgMaxWarp += metrics_1.avgMaxWarp;
			metrics.runTime += metrics_1.runTime;
		}
		metrics.avgStep /= N_SAMPLES;
		metrics.avgMaxWarp /= N_SAMPLES;
		metrics.runTime /= N_SAMPLES;
		// print results to stdout
		printf("%d,%d,%d,%f,%f,%f\n", TOTAL_N_PAGES, Nthreads, AvailablePages, metrics.avgStep, metrics.avgMaxWarp, metrics.runTime);
	}



	return 0;
}

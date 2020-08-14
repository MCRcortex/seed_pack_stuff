//"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v10.2\bin\nvcc.exe"  -ccbin "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Tools\MSVC\14.16.27023\bin\Hostx86\x64" -o pack main.cu -O3 -m=64 -arch=compute_61 -code=sm_61 -Xptxas -allow-expensive-optimizations=true -Xptxas -v
#include <iostream>
#include <chrono>
#include <fstream>
#include <algorithm>
#include <inttypes.h>
#include <bitset>
#include <iostream>
#include <vector>
#include <map>
#include <iomanip>
#include <fstream>
#include "lcg.h"


DEVICEABLE static int32_t random_next(lcg::Random *random, int bits) {
	*random = (*random * lcg::MULTIPLIER + lcg::ADDEND) & lcg::MASK;
	return (int32_t) (*random >> (48u - bits));
}

DEVICEABLE static int32_t random_next_int(lcg::Random *random, const uint16_t bound) {
	int32_t r = random_next(random, 31);
	const uint16_t m = bound - 1u;
	if ((bound & m) == 0) {
		r = (int32_t) ((bound * (uint64_t) r) >> 31u);
	} else {
		for (int32_t u = r;
			 u - (r = u % bound) + m < 0;
			 u = random_next(random, 31));
	}
	return r;
}

DEVICEABLE static int32_t random_next_int_nonpow(lcg::Random *random, const uint16_t bound) {
	int32_t r = random_next(random, 31);
	const uint16_t m = bound - 1u;
	for (int32_t u = r;
		 u - (r = u % bound) + m < 0;
		 u = random_next(random, 31));
  return r;
}

#define MAX_TREE_SEARCH 12
#define TREES_IN_CHUNK 2

//CHECK
#define WATERFALL_X 116 
#define WATERFALL_Y 76
#define WATERFALL_Z -31


#define POP_CHUNK_X ((WATERFALL_X-8)>>4)
#define POP_CHUNK_Z ((WATERFALL_Z-8)>>4)
#define WATERFALL_X_IN_POPULATION ((WATERFALL_X - 8)&15)
#define WATERFALL_Z_IN_POPULATION ((WATERFALL_Z - 8)&15)



#define TREE1_X (WATERFALL_X_IN_POPULATION - 5)
#define TREE1_Z (WATERFALL_Z_IN_POPULATION - 8)
#define TREE1_HEIGHT 5

#define TREE2_X (WATERFALL_X_IN_POPULATION - 3)
#define TREE2_Z (WATERFALL_Z_IN_POPULATION + 3)
#define TREE2_HEIGHT 5





//Should return a unique tree mask from 8 bit uint
DEVICEABLE static inline uint8_t GetTreeIndex(int innerX, int innerZ) {
	return ( (uint8_t)(innerX == TREE1_X && innerZ == TREE1_Z) << 0) |
			((uint8_t)(innerX == TREE2_X && innerZ == TREE2_Z) << 1) ;
}	



DEVICEABLE static inline bool TreeAtPosMatchesHeight(int innerX, int innerZ, int height) {
	return  ( (innerX == TREE1_X && innerZ == TREE1_Z && height == TREE1_HEIGHT)) ||
			((innerX == TREE2_X && innerZ == TREE2_Z && height == TREE2_HEIGHT));
}









DEVICEABLE static inline bool WaterfallMatch(lcg::Random rand) {
	// yellow flowers
	lcg::advance<774>(rand);
	// red flowers
	if (random_next(&rand, 1) == 0)
		lcg::advance<387>(rand);
	
	// brown mushroom
	if (random_next(&rand, 2) == 0)
		lcg::advance<387>(rand);
	
	// red mushroom
	if (random_next(&rand, 3) == 0)
		lcg::advance<387>(rand);
		
	// reeds
	lcg::advance<830>(rand);
	
	// pumpkins
	if (random_next(&rand, 5) == 0)
		lcg::advance<387>(rand);
	
	
	for (int i = 0; i < 50; i++) {
		bool waterfall_matches = random_next(&rand, 4) == WATERFALL_X_IN_POPULATION;
		waterfall_matches &= random_next_int(&rand, random_next_int_nonpow(&rand, 120) + 8) == WATERFALL_Y;
		waterfall_matches &= random_next(&rand, 4) == WATERFALL_Z_IN_POPULATION;
		if(waterfall_matches)
			return true;
	}
	return false;
}



DEVICEABLE static inline bool CheckChunkSeed(lcg::Random rand) {
	//Include dungeon skip which is 40
	lcg::advance<40+30+3686+3>(rand);
		
	if (random_next_int_nonpow(&rand,10) == 0)
		return false;
	
	uint8_t treeMask = 0;
	int treeCount = 0;
	for (int attempt = 0; attempt < MAX_TREE_SEARCH; attempt++) {
	  int x = lcg::next_int<16>(rand);
	  int z = lcg::next_int<16>(rand);
	  int treeHeight = 4 + lcg::next_int<3>(rand);
	  
	  uint8_t thisMask = GetTreeIndex(x, z);
	  if ((treeCount != TREES_IN_CHUNK) && (thisMask!=0) && ((thisMask&treeMask) == 0)) {
		if (!TreeAtPosMatchesHeight(x, z, treeHeight))
			//continue;
			return false;
		treeMask |= thisMask;
		// successful tree attempt
		treeCount++;
		lcg::advance<16>(rand); // not sure on this number // pretty sure it is
	  } else {
		// failed tree attempt
	  }
	  
	  if (treeCount == TREES_IN_CHUNK) {
		lcg::Random new_rand = rand;
		// test waterfall loop
		if (WaterfallMatch(new_rand))
			return true;
	  }
	}
	return false;
}


DEVICEABLE static inline bool doCheck(uint64_t seed) {
	lcg::Random chunkSeed = (seed ^ lcg::MULTIPLIER) & lcg::MASK;

	int64_t seedA = (((int64_t)lcg::next_long(chunkSeed))/2L)*2L+1L;
	int64_t seedB = (((int64_t)lcg::next_long(chunkSeed))/2L)*2L+1L;
	chunkSeed = ((((int64_t)POP_CHUNK_X) * seedA + ((int64_t)POP_CHUNK_Z) * seedB ^ seed) ^ lcg::MULTIPLIER)&lcg::MASK;
	

	
	//if(CheckChunkSeed(chunkSeed))
	//	return true;
	
	//Simulate 1 clay being spawned
	//lcg::advance<99-30>(chunkSeed);
	if(CheckChunkSeed(chunkSeed))
		return true;
	return false;
}





#define SEEDSPACE ((1LLU<<48)/8+1)




#define BLOCK_SIZE (256)
#define WORK_SIZE_BITS 24
#define SEEDS_PER_CALL ((1ULL << (WORK_SIZE_BITS)) * (BLOCK_SIZE))



__global__ __launch_bounds__(BLOCK_SIZE,2) void doo_bee_do_be_doo_ba(uint64_t offset, uint32_t* count, uint64_t* buffer) {
	uint64_t seed = blockIdx.x * blockDim.x + threadIdx.x + offset;
	if (seed > SEEDSPACE)
		return;
	
	seed *= 8;//Seed is now the time in nanoseconds
	
	seed += 8682522807148012LLU + 16LLU + 1LLU;//MUST UNCOMMENT + 1LLU//Uniquifier has been added to the seed 
	
	seed = (seed ^ lcg::MULTIPLIER) & lcg::MASK;//Make the new random object
	seed = lcg::next_long(seed);//Get the world seed
	
	if (doCheck(seed))
		buffer[atomicAdd(count, 1)] = seed;
	return;
}










#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)
	#include <windows.h>
	uint64_t getCurrentTimeMillis() {
		SYSTEMTIME time;
		GetSystemTime(&time);
		return (uint64_t)((time.wSecond * 1000) + time.wMilliseconds);
	}
#else
	#include <sys/time.h>
	uint64_t getCurrentTimeMillis() {
		struct timeval te; 
		gettimeofday(&te, NULL); // get current time
		uint64_t milliseconds = te.tv_sec*1000LL + te.tv_usec/1000; // calculate milliseconds
		return milliseconds;
	}
#endif
#define GPU_ASSERT(code) gpuAssert((code), __FILE__, __LINE__)
inline void gpuAssert(cudaError_t code, const char *file, int line) {
  if (code != cudaSuccess) {
	fprintf(stderr, "GPUassert: %s (code %d) %s %d\n", cudaGetErrorString(code), code, file, line);
	exit(code);
  }
}



uint32_t* count;
uint64_t* buffer;
std::ofstream seeds_output;
uint64_t start_time;

void doStep(uint64_t offset) {
	uint64_t start = getCurrentTimeMillis();
	*count = 0;
	doo_bee_do_be_doo_ba<<< 1ULL << WORK_SIZE_BITS, BLOCK_SIZE>>>(offset, count, buffer);
	GPU_ASSERT(cudaPeekAtLastError());
	GPU_ASSERT(cudaDeviceSynchronize());
	
	for(uint64_t index = 0; index < *count; index++)
		seeds_output << (buffer[index]& lcg::MASK) << std::endl;
	
	uint64_t end = getCurrentTimeMillis();
	//Not dividing by 1000000 cause dividing by milliseconds is equivalent to dividing by 1000
	std::cout << std::fixed << std::setprecision(2) << "Speed: " << (((double)SEEDS_PER_CALL/(end - start))/1000) << " mill seed/s," << //million seeds per second
		" step took " << (end - start) << " milliseconds," <<
		" seed count: " << *count << "," <<
		" ETA: " << (int)((((double)(SEEDSPACE-offset))/SEEDS_PER_CALL)*(end - start)/1000) << " seconds," <<
		" done " << std::fixed << std::setprecision(2) << (((double)offset/SEEDSPACE)*100) << "%" <<
		std::endl;
	
	
	//exit(0);
	/*
	uint64_t count = 0;
	uint64_t start = getCurrentTimeMillis();
	for(uint64_t seed =0;seed<100000000;seed++) {
		count += doCheck(seed);
	}*/
}

void setup() {
	seeds_output.open("seeds.txt");
	
	cudaSetDevice(0);
	GPU_ASSERT(cudaPeekAtLastError());
	GPU_ASSERT(cudaDeviceSynchronize());
	
	
	GPU_ASSERT(cudaMallocManaged(&count, sizeof(*count)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	GPU_ASSERT(cudaMallocManaged(&buffer, sizeof(*buffer) * (SEEDS_PER_CALL>>5)));
	GPU_ASSERT(cudaPeekAtLastError());
}

void done() {
	seeds_output.close();
}

int main() {
	std::cout << "Waterfall pop chunk x: " << POP_CHUNK_X << " waterfall x in pop chunk pos: " << WATERFALL_X_IN_POPULATION << std::endl;
	std::cout << "Waterfall pop chunk z: " << POP_CHUNK_Z << " waterfall z in pop chunk pos: " << WATERFALL_Z_IN_POPULATION << std::endl;
	std::cout << "Seeds per call/Step size: " << SEEDS_PER_CALL << std::endl;
	std::cout << "Seedspace size: " << SEEDSPACE << std::endl;
	std::cout << "Estimated steps: " << (SEEDSPACE/SEEDS_PER_CALL+1) << std::endl;
	
	start_time = getCurrentTimeMillis();
	
	setup();
	std::cout << "Starting now" << std::endl;
	for(uint64_t offset = 0; offset < (SEEDSPACE + SEEDS_PER_CALL); offset += SEEDS_PER_CALL)
		doStep(offset);
	done();
	cudaFree(count);
	GPU_ASSERT(cudaPeekAtLastError());
	cudaFree(buffer);
	GPU_ASSERT(cudaPeekAtLastError());
	
	std::cout << "Finished in " << ((getCurrentTimeMillis() - start_time)/1000) << " seconds" <<std::endl;
	return 0;
}








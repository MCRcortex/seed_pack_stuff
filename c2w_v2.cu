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
#include <chrono>
#include <mutex>
uint64_t millis() {return (std::chrono::duration_cast< std::chrono::milliseconds >(std::chrono::system_clock::now().time_since_epoch())).count();}



#define INPUT_FILE "seeds.txt"
#define OUTPUT_FILE "world_seeds.txt"
  


#define WORKER_COUNT (1ULL << 16)
#define BLOCK_SIZE (256)
#define SEEDS_PER_CALL ((WORKER_COUNT) * (BLOCK_SIZE))
#define VERIFY false






#ifndef CHUNK_X
#define CHUNK_X 6
#endif
#ifndef CHUNK_Z
#define CHUNK_Z -3
#endif




#define MASK48 ((1ULL << 48) - 1ULL)
#define MASK32 ((1ULL << 32) - 1ULL)
#define MASK16 ((1ULL << 16) - 1ULL)

#define M1 25214903917ULL
#define ADDEND1 11ULL

#define M2 205749139540585ULL
#define ADDEND2 277363943098ULL

#define M4 55986898099985ULL
#define ADDEND4 49720483695876ULL

inline __host__ __device__ int64_t nextLong(uint64_t* seed) {
    *seed = (*seed * M1 + ADDEND1) & MASK48;
    int32_t u = *seed >> 16;
    *seed = (*seed * M1 + ADDEND1) & MASK48;
    return ((uint64_t)u << 32) + (int32_t)(*seed >> 16);
}

inline __device__ void addSeed(uint64_t seed, uint64_t* seeds, uint64_t* seedCounter)
{
    seeds[atomicAdd(seedCounter, 1)] = seed;
}

inline __host__ __device__ uint64_t makeMask(int32_t bits) {
    return (1ULL << bits) - 1;
}
// can use __builtin_ctz() on cpu and __device__​ int __clzll ( long long int x ) on gpu
inline __host__ __device__ int32_t countTrailingZeroes(uint64_t v) {
    int32_t c;

    v = (v ^ (v - 1)) >> 1;

    for(c = 0; v != 0; c++)  {
        v >>= 1;
    }

    return c;
}

inline __host__ __device__ uint64_t modInverse(uint64_t x) {
    uint64_t inv = 0;
    uint64_t b = 1;
    for (int32_t i = 0; i < 16; i++) {
        inv |= (1ULL << i) * (b & 1);
        b = (b - x * (b & 1)) >> 1;
    }
    return inv;
}



const uint64_t firstMultiplier = (M2 * CHUNK_X + M4 * CHUNK_Z) & MASK16;
__constant__ int32_t multTrailingZeroes;
__constant__ uint64_t firstMultInv;

__constant__ int32_t xCount;
__constant__ int32_t zCount;
__constant__ int32_t totalCount;


inline __host__ __device__ uint64_t getChunkSeed(uint64_t worldSeed) {
    uint64_t seed = (worldSeed ^ M1) & MASK48;
    int64_t a = nextLong(&seed) / 2 * 2 + 1;
    int64_t b = nextLong(&seed) / 2 * 2 + 1;
    return (uint64_t)(((CHUNK_X * a + CHUNK_Z * b) ^ worldSeed) & MASK48);
}

inline __host__ __device__ uint64_t getPartialAddend(uint64_t partialSeed, int32_t bits) {
    uint64_t mask = makeMask(bits);
    return ((uint64_t)CHUNK_X) * (((int32_t)(((M2 * ((partialSeed ^ M1) & mask) + ADDEND2) & MASK48) >> 16)) / 2 * 2 + 1) +
           ((uint64_t)CHUNK_Z) * (((int32_t)(((M4 * ((partialSeed ^ M1) & mask) + ADDEND4) & MASK48) >> 16)) / 2 * 2 + 1);
}

inline __device__ void addWorldSeed(uint64_t firstAddend, uint64_t c, uint64_t chunkSeed, uint64_t* seeds, uint64_t* seedCounter) {
    if(countTrailingZeroes(firstAddend) < multTrailingZeroes)
        return;
    uint64_t bottom32BitsChunkseed = chunkSeed & MASK32;

    uint64_t b = (((firstMultInv * firstAddend) >> multTrailingZeroes) ^ (M1 >> 16)) & makeMask(16 - multTrailingZeroes);
    if (multTrailingZeroes != 0) {
        uint64_t smallMask = makeMask(multTrailingZeroes);
        uint64_t smallMultInverse = smallMask & firstMultInv;
        uint64_t target = (((b ^ (bottom32BitsChunkseed >> 16)) & smallMask) -
                                (getPartialAddend((b << 16) + c, 32 - multTrailingZeroes) >> 16)) & smallMask;
        b += (((target * smallMultInverse) ^ (M1 >> (32 - multTrailingZeroes))) & smallMask) << (16 - multTrailingZeroes);
    }
    uint64_t bottom32BitsSeed = (b << 16) + c;
    uint64_t target2 = (bottom32BitsSeed ^ bottom32BitsChunkseed) >> 16;
    uint64_t secondAddend = (getPartialAddend(bottom32BitsSeed, 32) >> 16);
    secondAddend &= MASK16;
    uint64_t topBits = ((((firstMultInv * (target2 - secondAddend)) >> multTrailingZeroes) ^ (M1 >> 32)) & makeMask(16 - multTrailingZeroes));

    for (; topBits < (1ULL << 16); topBits += (1ULL << (16 - multTrailingZeroes))) {
        if (getChunkSeed((topBits << 32) + bottom32BitsSeed) == chunkSeed) {
            addSeed((topBits << 32) + bottom32BitsSeed, seeds, seedCounter);
        }
    }
}

__global__ void crack(uint64_t* in_buff, const uint64_t in_count, uint64_t* out_buff, uint64_t* out_count) {
    uint64_t global_id = blockIdx.x * blockDim.x + threadIdx.x;
    if (global_id >= in_count)
        return;

    uint64_t chunkSeed = in_buff[global_id];
    int32_t x = CHUNK_X;
    int32_t z = CHUNK_Z;

	#if CHUNK_X == 0 && CHUNK_Z == 0
		addSeed(chunkSeed, out_buff, out_count);
	#else
		uint64_t f = chunkSeed & MASK16;
		uint64_t c = xCount == zCount ? chunkSeed & ((1ULL << (xCount + 1)) - 1) :
										chunkSeed & ((1ULL << (totalCount + 1)) - 1) ^ (1 << totalCount);
		#pragma unroll
		for (; c < (1ULL << 16); c += (1ULL << (totalCount + 1))) {
			uint64_t target = (c ^ f) & MASK16;
			uint64_t magic = (uint64_t)(x * ((M2 * ((c ^ M1) & MASK16) + ADDEND2) >> 16)) +
							 (uint64_t)(z * ((M4 * ((c ^ M1) & MASK16) + ADDEND4) >> 16));
			addWorldSeed(target - (magic & MASK16), c, chunkSeed, out_buff, out_count);
				#if CHUNK_X != 0
						addWorldSeed(target - ((magic + x) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_Z != 0 && CHUNK_X != CHUNK_Z
						addWorldSeed(target - ((magic + z) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_X != 0 && CHUNK_Z != 0 && CHUNK_X + CHUNK_Z != 0
						addWorldSeed(target - ((magic + x + z) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_X != 0 && CHUNK_X != CHUNK_Z
						addWorldSeed(target - ((magic + 2 * x) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_Z != 0 && CHUNK_X != CHUNK_Z
						addWorldSeed(target - ((magic + 2 * z) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_X != 0 && CHUNK_Z != 0 && CHUNK_X + CHUNK_Z != 0 && CHUNK_X * 2 + CHUNK_Z != 0
						addWorldSeed(target - ((magic + 2 * x + z) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_X != 0 && CHUNK_Z != 0 && CHUNK_X != CHUNK_Z && CHUNK_X + CHUNK_Z != 0 && CHUNK_X + CHUNK_Z * 2 != 0
						addWorldSeed(target - ((magic + x + 2 * z) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
				#if CHUNK_X != 0 && CHUNK_Z != 0 && CHUNK_X + CHUNK_Z != 0
						addWorldSeed(target - ((magic + 2 * x + 2 * z) & MASK16), c, chunkSeed, out_buff, out_count);
				#endif
		}
	#endif // !(CHUNK_X == 0 && CHUNK_Z == 0)
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



uint64_t* inBuff;
uint64_t* outBuff;
uint64_t* outCount;

std::ifstream inFile;
std::ofstream outFile;

void setup() {
	cudaSetDevice(0);
	GPU_ASSERT(cudaPeekAtLastError());
	GPU_ASSERT(cudaDeviceSynchronize());
	
	GPU_ASSERT(cudaMallocManaged(&inBuff, sizeof(*inBuff) * SEEDS_PER_CALL));
	GPU_ASSERT(cudaPeekAtLastError());
	
	GPU_ASSERT(cudaMallocManaged(&outBuff, sizeof(*outBuff) * (SEEDS_PER_CALL)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	GPU_ASSERT(cudaMallocManaged(&outCount, sizeof(*outCount)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	/*
	__constant__ int32_t multTrailingZeroes = countTrailingZeroes(firstMultiplier);
__constant__ uint64_t firstMultInv = modInverse(firstMultiplier >> multTrailingZeroes);

__constant__ int32_t xCount = countTrailingZeroes(CHUNK_X);
__constant__ int32_t zCount = countTrailingZeroes(CHUNK_Z);
__constant__ int32_t totalCount = countTrailingZeroes(CHUNK_X | CHUNK_Z);
*/
	auto tmp = countTrailingZeroes(firstMultiplier);
	GPU_ASSERT(cudaMemcpyToSymbol(multTrailingZeroes, &tmp, sizeof(multTrailingZeroes)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	auto tmp2 = modInverse(firstMultiplier >> multTrailingZeroes);
	GPU_ASSERT(cudaMemcpyToSymbol(firstMultInv, &tmp2, sizeof(firstMultInv)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	auto tmp3 = countTrailingZeroes(CHUNK_X);
	GPU_ASSERT(cudaMemcpyToSymbol(xCount, &tmp3, sizeof(xCount)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	auto tmp4 = countTrailingZeroes(CHUNK_Z);
	GPU_ASSERT(cudaMemcpyToSymbol(zCount, &tmp4, sizeof(zCount)));
	GPU_ASSERT(cudaPeekAtLastError());
	
	auto tmp5 = countTrailingZeroes(CHUNK_X | CHUNK_Z);
	GPU_ASSERT(cudaMemcpyToSymbol(totalCount, &tmp5, sizeof(totalCount)));
	GPU_ASSERT(cudaPeekAtLastError());
}

uint64_t fillBuffer() {
	uint64_t inCounter = 0;
	uint64_t curr_seed;
	for(inCounter = 0; inCounter < SEEDS_PER_CALL; inCounter++) {
		if (inFile >> curr_seed)
			inBuff[inCounter] = curr_seed;
		else
			break;
	}
	return inCounter;
}


int main() {
	inFile.open(INPUT_FILE);
	outFile.open(OUTPUT_FILE);
	setup();
	
	uint64_t in_buff_count = fillBuffer();
	while (in_buff_count != 0) {
		uint64_t start = millis();
		*outCount = 0;
		crack<<<WORKER_COUNT,BLOCK_SIZE>>>(inBuff, in_buff_count, outBuff, outCount);
		GPU_ASSERT(cudaPeekAtLastError());
		GPU_ASSERT(cudaDeviceSynchronize());
		
		
		if(VERIFY) {
			for (uint64_ {t outIndex = 0; outIndex < *outCount; outIndex++) {
				uint64_t chunkSeed = getChunkSeed(outBuff[outIndex]);
				bool match = false;
				for(uint64_t i = 0; i < in_buff_count; i++) {
					if (chunkSeed == inBuff[i]) {
						match = true;
						break;
					}
				}
				if (!match) {
					std::cout << "Seed: " << outBuff[outIndex] << " was not in original chunk seed list" << std::endl;
					exit(-1);
				}
			}
		}
		
		for (uint64_t outIndex = 0; outIndex < *outCount; outIndex++)
			outFile << outBuff[outIndex] << std::endl;
		
		std::cout << "Processed " << in_buff_count << " chunk seeds into " << *outCount << " world seeds in " << ((millis() - start)/1000) << " seconds" << std::endl;
		
		in_buff_count = fillBuffer();
	}
	outFile.close();
	std::cout << "Done" << std::endl;
	return 0;
}


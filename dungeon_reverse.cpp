//NEEDS LIBSEEDFINDING

//cl main.cpp -o do.exe -O2 /EHcs
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




#define THREADS 5
#define IN_FILE "chunk_seeds.txt"
#define OUT_FILE "seeds.txt"


void ProcessChunkSeed(uint64_t seed);
std::vector<std::string> chunkSeedsOut;
std::mutex seed_mutex;
void AddOutputSeed(uint64_t seed) {
	std::string str_rep = std::to_string(seed);
	seed_mutex.lock();
	chunkSeedsOut.push_back(str_rep);
	seed_mutex.unlock();
}

int main2() {
	std::cout << "Loading inital seeds" << std::endl;
	uint64_t start_time = millis();
	std::vector<uint64_t> chunkSeeds;
	{
		std::ifstream chunkSeedsInFile(IN_FILE);
		uint64_t curr;
		while (chunkSeedsInFile >> curr)
			chunkSeeds.push_back(curr);
		chunkSeedsInFile.close();
	}
	const uint32_t chunkSeeds_count = chunkSeeds.size();
	std::cout << "Loaded seeds in " << ((millis() - start_time)/1000) << " seconds" << std::endl;
	
	
	if (chunkSeeds_count == 0) {
		std::cout << "No seeds loaded for processing, exiting" << std::endl;
		exit(1);
	}
	
	auto doWork = [chunkSeeds_count, &chunkSeeds](uint32_t threadId ) {
		for (uint64_t index = threadId; index < chunkSeeds_count + 1; index += THREADS) {
			if (index > chunkSeeds_count - 1)
				return;
			ProcessChunkSeed(chunkSeeds[index]);
		}
	};
	
	start_time = millis();
	std::cout << "Processing " << chunkSeeds_count << " seeds on " << THREADS << " threads" << std::endl;
	
	std::vector<std::thread> threads;
	for(uint32_t i = 0; i < THREADS;i++)
		threads.push_back(std::thread(doWork, i));
		
	for(auto& t : threads)
		t.join();
	
	uint64_t delta_time = millis() - start_time;
	std::cout << "Processed " << chunkSeeds_count << " seeds into " << chunkSeedsOut.size() << " seeds in " << (delta_time/1000) << " seconds" << std::endl;

	start_time = millis();
	std::ofstream outFile(OUT_FILE);
	for (std::string seed : chunkSeedsOut)
		outFile << seed << std::endl;
	outFile.close();
	std::cout << "Saved output seeds in " << ((millis() - start_time)/1000) << " seconds" << std::endl;
	return 0;
}

















#include "lcg.h"
static inline void PopulateDungeonChest(lcg::Random& rand) {
	for(uint8_t k4 = 0; k4 < 8; k4++) {
		uint8_t lootItem = lcg::next_int<11>(rand);
		bool isLoot = true;
		switch (lootItem) {
			case 8:
				if (lcg::next_int<2>(rand) != 0)
					break;
			case 1:
			case 3:
			case 4:
			case 5:
				lcg::advance<1>(rand);
				break;
			case 7:
				lcg::next_int<100>(rand);
				break;
			case 9:
				if (lcg::next_int<10>(rand) == 0)
					lcg::advance<1>(rand);
				break;
			default:
				isLoot = false;
		}
		if (isLoot)
			lcg::next_int<27>(rand);
	}
}



struct LCG {
	uint64_t multiplier;
	uint64_t addend;
};

template<int64_t N>
LCG combineLCG() {return {lcg::combined_lcg<N>::multiplier, lcg::combined_lcg<N>::addend};}


const LCG DUNGEON_SIZE_SKIP[] = {combineLCG<((0+2)*2+1+2)*((0+2)*2+1+2)>(), combineLCG<((0+2)*2+1+2)*((1+2)*2+1+2)>(),
								 combineLCG<((1+2)*2+1+2)*((0+2)*2+1+2)>(), combineLCG<((1+2)*2+1+2)*((1+2)*2+1+2)>()}; 

//Each index should skip 5 LCG's, START AT 0 SKIP, is the amount of skips to finish dungeon test
const LCG REMAINING_SKIP[] = {combineLCG<0>(), combineLCG<5*1>(), combineLCG<5*2>(), combineLCG<5*3>(), combineLCG<5*4>(), combineLCG<5*5>(), combineLCG<5*6>(), combineLCG<5*7>()}; 



//Gonna have to do something fancy here, as a dungeon spawns next to a cave with an opening, that opening stops chests from being able to generate

static inline bool SimulateDungeonLootSpawn(lcg::Random& rand, int8_t size_x, int8_t size_z, int loopTimes = 2) {
	bool spawned_chest = false;
	for(int i2 = 0; i2 < loopTimes; i2++)
	{
		for(int l2 = 0; l2 < 3; l2++)
		{
			int8_t x_pos = (lcg::dynamic_next_int(rand, (size_x + 2) * 2 + 1) - size_x - 2);
			int8_t z_pos = (lcg::dynamic_next_int(rand, (size_z + 2) * 2 + 1) - size_z - 2);
			
			
			
			//If its not next to a wall
			if (!((x_pos == (size_x + 2) || x_pos == (-size_x - 2)) ||
				  (z_pos == (size_z + 2) || z_pos == (-size_z - 2))))
				continue;
				
			//If its in a corner, abort
			
			if ((x_pos == (size_x + 2) || x_pos == (-size_x - 2)) &&
				(z_pos == (size_z + 2) || z_pos == (-size_z - 2)))
				continue;
			//if (!posValid)
			//	continue;
			
			spawned_chest = true;
			//Simulate loot gen
			PopulateDungeonChest(rand);
			break;
		}
	}
	return spawned_chest;
}





//TODO: change so that it tries 0 chest spawns, 1 chest spawns and 2 chest spawns,  JUST DO IT LIKE ITS NOT A VALID POSITION AS WE still need to skip required amont of calls


static inline bool doesMatch(uint64_t chunkSeed, uint64_t wanted) {
	for(uint8_t dungeon_index = 0; dungeon_index < 8; dungeon_index++) {
		//skip position choosing, this is the same whether a dungeon spawned or not
		lcg::advance<1>(chunkSeed);
		uint8_t spawn_height = lcg::next_int<128>(chunkSeed);
		
		//If the dungeon tried to spawn in the air, just skip it, cause it wont
		if (spawn_height > 85) {//87 is the rough height of the mountain, doesnt need to be exact
			lcg::advance<3>(chunkSeed);
			continue;
		}
		
		
		lcg::advance<1>(chunkSeed);
		
		//Choosing a size is done no matter if a dungeon is generated or not
		uint8_t size_x = lcg::next_int<2>(chunkSeed);
		uint8_t size_z = lcg::next_int<2>(chunkSeed);
		uint64_t curChunkSeed = chunkSeed;
		uint8_t size_index = size_x * 2 + size_z;
		curChunkSeed = (DUNGEON_SIZE_SKIP[size_index].multiplier * curChunkSeed + DUNGEON_SIZE_SKIP[size_index].addend) & lcg::MASK;
		uint8_t remaining_dungeons_skip = (8 - dungeon_index - 1);//How many dungeons didnt spawn, use this with a LUT to skip the correct number of calls
		
		//TODO skip/simulate dungeon loot here
		//SimulateDungeonLootSpawn(curChunkSeed, size_x, size_z);
		
		SimulateDungeonLootSpawn(curChunkSeed, size_x, size_z);
		
		//Skip the mob spawner type being choosen
		lcg::advance<1>(curChunkSeed);
		curChunkSeed = (REMAINING_SKIP[remaining_dungeons_skip].multiplier * curChunkSeed + REMAINING_SKIP[remaining_dungeons_skip].addend) & lcg::MASK;
		
		//Skip clay, no gen
		//lcg::advance<30>(curChunkSeed);
		
		//std::cout << (lcg::seed2dfz(wanted)-lcg::seed2dfz(curChunkSeed)) << "  "<<(int)remaining_dungeons_skip<< std::endl;
		
		if(curChunkSeed == wanted)
			return true;
		
		
		//1 gen clay
		//lcg::advance<99-30>(curChunkSeed);
		//if(CheckChunkSeedAfterClay(curChunkSeed))
		//	return true;
	}
	return false;
}


#define CHECK_CLAY_1_BACK false

#define SEARCHBACK_SIZE 200
std::vector<uint64_t> nonMatching;
std::mutex access_lock;
void ProcessChunkSeed(uint64_t seed) {
	lcg::advance<40>(seed);//Seed is now after the no dungeon assumption
	
	if(CHECK_CLAY_1_BACK) {
		lcg::advance<30>(seed);//Seed is now after the clay gen
		
		lcg::advance<-99>(seed);//Reverse with the number of calls to generate a clay spot
	}
	
	uint64_t seed_back = seed;
	//seed_back is now before clay check
	
	//Reverse alot, then check each point if a dungeon could generate, this is dodgy 200%
	//40 is the min with no dungeons
	lcg::advance<-SEARCHBACK_SIZE>(seed_back);
	uint8_t matches = 0;
	for(uint64_t i = 0; i <  SEARCHBACK_SIZE - 30; i++) {//30 was just cause at 40 index, there must not have been any dungeons
		if(doesMatch(seed_back, seed)) {
			AddOutputSeed(seed_back);
			matches++;
			//std::cout << (int)i << std::endl;
		}
		//std::cout << (int)i << std::endl;
		lcg::advance<1>(seed_back);
	}
	if (matches == 0) {
		access_lock.lock();
		nonMatching.push_back(seed);
		access_lock.unlock();
		//std::cout << "Seed " << seed << " had no backwards dungeon matches, THIS SHOULD NOT BE POSSIBLE i think?"<< std::endl;
	}
}





int main(){
	main2();
	std::cout << nonMatching.size() << " seeds had no matches with dungeons" << std::endl;
	//std::cout << nonMatching[0] << std::endl;
	

	//uint64_t s = 118689260445047;
	//lcg::advance<-40+69>(s);
	//ProcessChunkSeed(s);
	//std::cout << nonMatching.size() << std::endl;

	return 0;
}




//











import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';

export class Memez {
  #client: SuiClient;
  constructor(fullNodeUrl: string) {
    this.#client = new SuiClient({
      url: fullNodeUrl || getFullnodeUrl('testnet'),
    });
  }
}

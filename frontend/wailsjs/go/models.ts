export namespace main {
	
	export class Quote {
	    provider: string;
	    name: string;
	    symbol: string;
	    price: number;
	    percent: number;
	    change: number;
	    phase: string;
	    timestamp: number;
	
	    static createFrom(source: any = {}) {
	        return new Quote(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.provider = source["provider"];
	        this.name = source["name"];
	        this.symbol = source["symbol"];
	        this.price = source["price"];
	        this.percent = source["percent"];
	        this.change = source["change"];
	        this.phase = source["phase"];
	        this.timestamp = source["timestamp"];
	    }
	}
	export class Settings {
	    provider: string;
	    marketType: string;
	    symbol: string;
	    displayName: string;
	    cryptoSymbol: string;
	    customUrl: string;
	    customHeaders: string;
	    customValuePath: string;
	    customPercentPath: string;
	    pollSeconds: number;
	    riseThreshold: number;
	    fallThreshold: number;
	    soundEnabled: boolean;
	    voiceEnabled: boolean;
	    customUpSound: string;
	    customDownSound: string;
	    customCowSound: string;
	    volume: number;
	    alwaysOnTop: boolean;
	    runOnStartup: boolean;
	    petSize: string;
	    staleSleepMinutes: number;
	
	    static createFrom(source: any = {}) {
	        return new Settings(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.provider = source["provider"];
	        this.marketType = source["marketType"];
	        this.symbol = source["symbol"];
	        this.displayName = source["displayName"];
	        this.cryptoSymbol = source["cryptoSymbol"];
	        this.customUrl = source["customUrl"];
	        this.customHeaders = source["customHeaders"];
	        this.customValuePath = source["customValuePath"];
	        this.customPercentPath = source["customPercentPath"];
	        this.pollSeconds = source["pollSeconds"];
	        this.riseThreshold = source["riseThreshold"];
	        this.fallThreshold = source["fallThreshold"];
	        this.soundEnabled = source["soundEnabled"];
	        this.voiceEnabled = source["voiceEnabled"];
	        this.customUpSound = source["customUpSound"];
	        this.customDownSound = source["customDownSound"];
	        this.customCowSound = source["customCowSound"];
	        this.volume = source["volume"];
	        this.alwaysOnTop = source["alwaysOnTop"];
	        this.runOnStartup = source["runOnStartup"];
	        this.petSize = source["petSize"];
	        this.staleSleepMinutes = source["staleSleepMinutes"];
	    }
	}

}


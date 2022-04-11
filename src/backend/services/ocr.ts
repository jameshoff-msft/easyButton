import { ComputerVisionClient, ComputerVisionModels } from "@azure/cognitiveservices-computervision"
import { ApiKeyCredentials } from "@azure/ms-rest-js"
import { BpaServiceObject } from "../engine/types";

export class Ocr {

    private _client: ComputerVisionClient

    constructor(endpoint: string, apikey: string) {
        this._client = new ComputerVisionClient(
            new ApiKeyCredentials({ inHeader: { 'Ocp-Apim-Subscription-Key': apikey } }), endpoint);
    }

    private sleep = (ms: number) => {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    public process = async (input: BpaServiceObject): Promise<BpaServiceObject> => {
        const readResult: ComputerVisionModels.ReadResult[] = await this.execute(input.data)
        console.log(`1`)
        const textOut: string = this.toText(readResult)
        for(let i=0;i<25;i++){
            await this.sleep(1000)
            console.log(`${textOut}`)
        }
        console.log("2")
        const result: BpaServiceObject = {
            data: textOut,
            type: 'text',
            label: 'ocr',
            bpaId: input.bpaId,
            projectName: input.projectName
        }
        console.log("3")
        return result
    }

    private execute = async (fileBuffer: Buffer): Promise<ComputerVisionModels.ReadResult[]> => {
        let fileStream = await this._client.readInStream(fileBuffer);
        //Operation ID is last path segment of operationLocation (a URL)
        let operation: string = fileStream.operationLocation.split('/').slice(-1)[0];
        // Wait for read recognition to complete
        // result.status is initially undefined, since it's the result of read
        let status: string = ''
        let result: ComputerVisionModels.GetReadResultResponse = null
        while (status !== 'succeeded') {
            console.log("in ocr read loop")
            result = await this._client.getReadResult(operation);
            status = result.status
            console.log(`ocr status: ${status}`)
            await this.sleep(1000);
        }
        console.log("completed")
        for(let i=0;i<25;i++){
            console.log(`${JSON.stringify(result.analyzeResult.readResults)}`)
            await this.sleep(1000)
        }
            
        return result.analyzeResult.readResults;
    }

    public toText = (results: ComputerVisionModels.ReadResult[]): string => {
        console.log(`converting ocr output to string`)
        let outString = ""
        for (const page of results) {
            for (const line of page.lines) {
                outString += " " + line.text
            }
        }
        for(let i=0;i<25;i++){
            console.log(`totext ${JSON.stringify(outString)}`)
        }
        return outString.replace('[A-Za-z0-9 *!$%&()?<>{}]+', '')
    }
}
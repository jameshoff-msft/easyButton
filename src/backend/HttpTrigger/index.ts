import { AzureFunction, Context, HttpRequest } from "@azure/functions"
//import { serviceCatalog } from "../engine/serviceCatalog";

const httpTrigger: AzureFunction = async function (context: Context, req: HttpRequest): Promise<void> {
    context.log('HTTP trigger function processed a request.');

    context.res = {
        
       // body: serviceCatalog
    };

};

export default httpTrigger;
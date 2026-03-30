const AWS = require("aws-sdk");
const ssm = new AWS.SSM({ region: process.env.AWS_REGION || "<region>" });

async function getDBParameters() {
  try {
    const params = {
      // Names: ["DB_HOST", "DB_USERNAME", "DB_PASSWORD", "DB_NAME"], // list of SSM parameter names
      Names: [
        "DB_HOST_<environment>_<region>",
        "DB_USERNAME_<environment>_<region>",
        "DB_PASSWORD_<environment>_<region>",
        "DB_NAME_<environment>_<region>",
        "DB_PORT_<environment>_<region>",
      ], // list of SSM parameter names
      WithDecryption: true,
    };

    const response = await ssm.getParameters(params).promise();

    const result = {};
    for (const param of response.Parameters) {
      result[param.Name] = param.Value;
    }
    // for double safety purpose store the values in process environment as well
    // process.env.DB_HOST = result.DB_HOST;
    // process.env.DB_USERNAME = result.DB_USERNAME;
    // process.env.DB_PASSWORD = result.DB_PASSWORD;
    // process.env.DB_NAME = result.DB_NAME;
    console.log("Fetched parameters:", result);
    return result;
  } catch (error) {
    console.error("Error fetching parameters:", error);
    throw error;
  }
}

// // Usage
// getDBParameters().then(dbParams => {
//   console.log('DB Host:', dbParams.DB_HOST);
// });

module.exports = (async () => {
  try {
    const param = await getDBParameters();

    return Object.freeze({
      DB_HOST: param["DB_HOST_<environment>_<region>"],
      DB_USER: param["DB_USERNAME_<environment>_<region>"],
      DB_PASSWORD: param["DB_PASSWORD_<environment>_<region>"],
      DB_DATABASE: param["DB_NAME_<environment>_<region>"],
      DB_PORT: param["DB_PORT_<environment>_<region>"],
    });
  } catch (error) {
    console.error("Failed to load database configuration:", error);
    return Object.freeze({
      DB_HOST: process.env.DB_HOST || "",
      DB_USER: process.env.DB_USER || "",
      DB_PASSWORD: process.env.DB_PASSWORD || "",
      DB_DATABASE: process.env.DB_DATABASE || "",
      DB_PORT: process.env.DB_PORT || "",
    });
  }
})();
// DB_HOST: param.DB_HOST,
// DB_USER: param.DB_USERNAME,
// DB_PASSWORD: param.DB_PASSWORD,
// DB_DATABASE: param.DB_NAME,

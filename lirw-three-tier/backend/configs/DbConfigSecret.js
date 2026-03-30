const AWS = require("aws-sdk");
const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || "<region>",
});

async function getDatabaseSecrets() {
  try {
    const secretName = process.env.DB_SECRET_NAME || "<secret-name>";
    const data = await secretsManager
      .getSecretValue({ SecretId: secretName })
      .promise();

    if ("SecretString" in data) {
      return JSON.parse(data.SecretString);
    } else {
      throw new Error("Secret binary not supported");
    }
  } catch (error) {
    console.error("Error retrieving secret:", error);
    throw error;
  }
}

module.exports = (async () => {
  try {
    const secrets = await getDatabaseSecrets();
    return Object.freeze({
      DB_HOST: secrets["DB_HOST_<environment>_<region>"],
      DB_USER: secrets["DB_USERNAME_<environment>_<region>"],
      DB_PASSWORD: secrets["DB_PASSWORD_<environment>_<region>"],
      DB_DATABASE: secrets["DB_NAME_<environment>_<region>"],
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

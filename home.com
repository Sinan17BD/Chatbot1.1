import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpRequest.BodyPublishers;
import java.util.Scanner;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

public class PoemChatbot {

    // Replace this with your actual OpenAI API key
    private static final String OPENAI_API_KEY = "YOUR_OPENAI_API_KEY";

    // OpenAI Chat Completion API endpoint
    private static final String OPENAI_API_URL = "https://api.openai.com/v1/chat/completions";

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    public PoemChatbot() {
        httpClient = HttpClient.newHttpClient();
        objectMapper = new ObjectMapper();
    }

    /**
     * Generates a poem based on the user's first line.
     * @param firstLine The first line of the poem provided by the user.
     * @return The generated full poem as a String.
     * @throws IOException
     * @throws InterruptedException
     */
    public String generatePoem(String firstLine) throws IOException, InterruptedException {
        // Craft the prompt to instruct the AI to write a poem continuing the user's first line
        String prompt = "You are a creative poet. Continue this poem starting with the line:\n\"" + firstLine + "\"\n" +
                "Generate a full poem with 12 more lines in a poetic style.";

        // Build JSON request body for OpenAI Chat Completion API
        ObjectNode requestBody = objectMapper.createObjectNode();
        requestBody.put("model", "gpt-4"); // or "gpt-3.5-turbo" if gpt-4 not available
        ArrayNode messages = objectMapper.createArrayNode();

        // System message to set the assistant behavior
        ObjectNode systemMessage = objectMapper.createObjectNode();
        systemMessage.put("role", "system");
        systemMessage.put("content", "You are a helpful assistant that writes poems.");

        // User message with the prompt
        ObjectNode userMessage = objectMapper.createObjectNode();
        userMessage.put("role", "user");
        userMessage.put("content", prompt);

        messages.add(systemMessage);
        messages.add(userMessage);

        requestBody.set("messages", messages);
        requestBody.put("max_tokens", 300);
        requestBody.put("temperature", 0.8);

        String requestBodyString = objectMapper.writeValueAsString(requestBody);

        // Build HTTP POST request
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(OPENAI_API_URL))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + OPENAI_API_KEY)
                .POST(BodyPublishers.ofString(requestBodyString))
                .build();

        // Send request and get response
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            throw new IOException("OpenAI API request failed with status code " + response.statusCode() + ": " + response.body());
        }

        // Parse JSON response to extract the generated poem text
        ObjectNode responseJson = (ObjectNode) objectMapper.readTree(response.body());
        String poem = responseJson
                .withArray("choices")
                .get(0)
                .get("message")
                .get("content")
                .asText();

        return poem.trim();
    }

    public static void main(String[] args) {
        PoemChatbot chatbot = new PoemChatbot();
        Scanner scanner = new Scanner(System.in);

        System.out.println("Welcome to the Poem-Writing Chatbot!");
        System.out.println("Please enter the first line of your poem:");

        String firstLine = scanner.nextLine().trim();

        if (firstLine.isEmpty()) {
            System.out.println("You must enter a first line to generate a poem.");
            scanner.close();
            return;
        }

        try {
            System.out.println("\nGenerating poem...\n");
            String poem = chatbot.generatePoem(firstLine);
            System.out.println("Here is your generated poem:\n");
            System.out.println(poem);
        } catch (Exception e) {
            System.err.println("Error generating poem: " + e.getMessage());
        } finally {
            scanner.close();
        }
    }
}

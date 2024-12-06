// Camel-K Integration in Java DSL
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.model.rest.RestParamType;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

public class CurrencyProxy extends RouteBuilder {
    @Override
    public void configure() throws Exception {
        // Define the REST API endpoint
        rest("/api/currency")
            .get()
            .param().name("date").type(RestParamType.query).required(false).endParam()
            .to("direct:getCurrency");
        // Route for calling the external SOAP service
        from("direct:getCurrency")
	    .process(exchange -> {
                // Получаем дату из заголовка или подставляем текущую
                String date = exchange.getIn().getHeader("date", String.class);
                if (date == null) {
                    date = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd"));
                    exchange.getIn().setHeader("date", date);
                }
            })
            .setHeader("Content-Type", constant("text/xml; charset=utf-8"))
            .setHeader("SOAPAction", constant("http://web.cbr.ru/GetCursOnDate"))
            .setBody().simple("""
              <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                <soap:Body>
                  <GetCursOnDate xmlns="http://web.cbr.ru/">
                    <On_date>${header.date}</On_date>
                  </GetCursOnDate>
                </soap:Body>
              </soap:Envelope>
            """)
            .to("http://www.cbr.ru/DailyInfoWebServ/DailyInfo.asmx?bridgeEndpoint=true")
            .unmarshal().jacksonxml() // Convert SOAP XML response to a Java object
            .marshal().json()         // Convert the Java object to JSON format
            .log("Response: ${body}"); // Log the response
    }
}

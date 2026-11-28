FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B -DskipTests package

FROM public.ecr.aws/lambda/java:21
COPY --from=build /workspace/target/report-event-consumer.jar ${LAMBDA_TASK_ROOT}/lib/app.jar
CMD ["cl.brarriodigital.lambda.RequestEventHandler::handleRequest"]

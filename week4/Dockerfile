FROM adoptopenjdk/openjdk11:jre-11.0.8_10-debianslim

RUN adduser --system --group hello
USER hello:hello

WORKDIR /home/hello
COPY --chown=hello ./hello-spring-boot-0.1.0.jar .

EXPOSE 8080
CMD ["java", "-jar", "hello-spring-boot-0.1.0.jar"]

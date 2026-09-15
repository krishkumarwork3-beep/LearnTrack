package com.learntrack;

import javafx.application.Application;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.BorderPane;
import javafx.stage.Stage;

/**
 * Application entry point.
 * Implementation Plan reference: section 2 (Architecture), section 14 (UI Screens).
 *
 * Responsible for:
 *  - initializing the JDBC connection (util.DBConnection)
 *  - running schema.sql on first launch if the DB is empty
 *  - showing the Timetable Setup Wizard if no active semester exists yet
 *  - otherwise loading straight into DashboardView inside a BorderPane
 *    with the sidebar nav (Dashboard / Topics / Skills / Calendar / Settings)
 */
public class MainApp extends Application {

    @Override
    public void start(Stage primaryStage) {
        // TODO: DBConnection.init(); run schema.sql if needed
        // TODO: check SemesterDAO for an ACTIVE semester
        //   -> none found: launch ui.setup.TimetableSetupWizard
        //   -> found: call service.SemesterReplanService.regenerateSemesterPlan(today)
        //             then show ui.views.DashboardView

        BorderPane root = new BorderPane();
        root.setCenter(new Label("LearnTrack — scaffold only, see Implementation Plan"));

        primaryStage.setTitle("LearnTrack");
        primaryStage.setScene(new Scene(root, 1000, 700));
        primaryStage.show();
    }

    public static void main(String[] args) {
        launch(args);
    }
}

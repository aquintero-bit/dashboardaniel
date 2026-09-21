import React from "react";
import { createRoot } from "react-dom/client";
import "./estilos.css";
import App from "../febeca-admin.jsx";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
